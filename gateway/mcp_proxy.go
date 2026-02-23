package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os/exec"
	"sync"
)

// MCPProxy manages a Chapel MCP subprocess and bridges STDIO to HTTP/SSE.
// It intercepts tools/list to inject gateway tools and dispatches gateway
// tool calls locally without forwarding to the subprocess.
type MCPProxy struct {
	binaryPath string

	mu    sync.Mutex
	cmd   *exec.Cmd
	stdin io.WriteCloser

	// responseCh receives JSON-RPC responses (messages with "id") from readLoop.
	responseCh chan []byte

	// SSE subscribers receive JSON-RPC notifications from the subprocess.
	subs   map[chan []byte]struct{}
	subsMu sync.Mutex

	// Gateway tool handlers (set after construction).
	resolver *Resolver
	setec    *SetecClient
	audit    *AuditLog
}

// NewMCPProxy creates a proxy for the given Chapel binary.
func NewMCPProxy(binaryPath string) *MCPProxy {
	return &MCPProxy{
		binaryPath: binaryPath,
		responseCh: make(chan []byte, 1),
		subs:       make(map[chan []byte]struct{}),
	}
}

// Start launches the Chapel MCP subprocess and sends the MCP initialize
// handshake so the subprocess is ready to handle tool calls.
func (p *MCPProxy) Start() error {
	p.mu.Lock()

	cmd := exec.Command(p.binaryPath, "--mode=mcp")
	stdin, err := cmd.StdinPipe()
	if err != nil {
		p.mu.Unlock()
		return fmt.Errorf("stdin pipe: %w", err)
	}
	stdoutPipe, err := cmd.StdoutPipe()
	if err != nil {
		p.mu.Unlock()
		return fmt.Errorf("stdout pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		p.mu.Unlock()
		return fmt.Errorf("start subprocess: %w", err)
	}

	p.cmd = cmd
	p.stdin = stdin

	// readLoop is the sole reader from stdout. It routes responses to
	// responseCh and broadcasts notifications to SSE subscribers.
	go p.readLoop(bufio.NewReader(stdoutPipe))

	p.mu.Unlock()

	// Send MCP initialize handshake so the subprocess is ready for tool calls.
	initReq, _ := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      0,
		"method":  "initialize",
		"params": map[string]any{
			"protocolVersion": "2025-03-26",
			"capabilities":    map[string]any{},
			"clientInfo": map[string]any{
				"name":    "rj-gateway",
				"version": "2.1.0",
			},
		},
	})
	log.Printf("mcp: sending initialize handshake")
	resp, err := p.SendRequest(initReq)
	if err != nil {
		log.Printf("warning: mcp initialize failed: %v", err)
	} else {
		log.Printf("mcp: initialize response: %s", string(resp))
	}

	return nil
}

// Stop terminates the subprocess.
func (p *MCPProxy) Stop() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.stdin != nil {
		p.stdin.Close()
	}
	if p.cmd != nil && p.cmd.Process != nil {
		return p.cmd.Process.Kill()
	}
	return nil
}

// readLoop is the sole reader from the subprocess stdout. It routes
// JSON-RPC responses (messages with "id") to responseCh and broadcasts
// notifications (messages without "id") to SSE subscribers.
func (p *MCPProxy) readLoop(stdout *bufio.Reader) {
	log.Printf("mcp: readLoop started")
	for {
		line, err := stdout.ReadBytes('\n')
		if err != nil {
			if err != io.EOF {
				log.Printf("mcp subprocess read error: %v", err)
			}
			log.Printf("mcp: readLoop exiting (err=%v)", err)
			close(p.responseCh)
			return
		}

		log.Printf("mcp: readLoop got line (%d bytes): %.200s", len(line), string(line))

		var msg map[string]json.RawMessage
		if json.Unmarshal(line, &msg) != nil {
			log.Printf("mcp: readLoop skipping non-JSON line")
			continue // skip non-JSON lines
		}

		if _, hasID := msg["id"]; hasID {
			// Response to a request — route to SendRequest waiter.
			log.Printf("mcp: readLoop routing response (has id) to responseCh")
			p.responseCh <- line
			log.Printf("mcp: readLoop sent to responseCh")
		} else {
			// Notification — broadcast to SSE subscribers.
			log.Printf("mcp: readLoop broadcasting notification")
			p.broadcast(line)
		}
	}
}

// broadcast sends a message to all SSE subscribers.
func (p *MCPProxy) broadcast(data []byte) {
	p.subsMu.Lock()
	defer p.subsMu.Unlock()
	for ch := range p.subs {
		select {
		case ch <- data:
		default:
			// Drop if subscriber is slow.
		}
	}
}

// subscribe registers an SSE listener.
func (p *MCPProxy) subscribe() chan []byte {
	ch := make(chan []byte, 64)
	p.subsMu.Lock()
	p.subs[ch] = struct{}{}
	p.subsMu.Unlock()
	return ch
}

// unsubscribe removes an SSE listener.
func (p *MCPProxy) unsubscribe(ch chan []byte) {
	p.subsMu.Lock()
	delete(p.subs, ch)
	p.subsMu.Unlock()
	close(ch)
}

// SendRequest writes a JSON-RPC request to the subprocess and waits for
// the response from readLoop. Serialized: only one request at a time.
func (p *MCPProxy) SendRequest(request []byte) ([]byte, error) {
	log.Printf("mcp: SendRequest acquiring lock")
	p.mu.Lock()
	defer p.mu.Unlock()
	log.Printf("mcp: SendRequest lock acquired, writing %d bytes", len(request))

	// Write request followed by newline.
	if _, err := p.stdin.Write(append(request, '\n')); err != nil {
		return nil, fmt.Errorf("write to subprocess: %w", err)
	}
	log.Printf("mcp: SendRequest wrote to stdin, waiting for response")

	// Wait for response from readLoop.
	line, ok := <-p.responseCh
	if !ok {
		return nil, fmt.Errorf("subprocess closed")
	}
	log.Printf("mcp: SendRequest got response (%d bytes)", len(line))

	return line, nil
}

// gatewayToolNames are tools handled by the gateway, not the Chapel subprocess.
var gatewayToolNames = map[string]bool{
	"juggler_resolve_composite": true,
	"juggler_setec_list":        true,
	"juggler_setec_get":         true,
	"juggler_setec_put":         true,
	"juggler_audit_log":         true,
}

// HandleRPC handles POST /mcp JSON-RPC requests.
// It intercepts tools/list to inject gateway tools and dispatches
// gateway-specific tool calls locally.
func (p *MCPProxy) HandleRPC(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "read body: "+err.Error(), http.StatusBadRequest)
		return
	}

	// Parse the request to check if it's a gateway-handled tool call.
	var req struct {
		JSONRPC string          `json:"jsonrpc"`
		ID      json.RawMessage `json:"id"`
		Method  string          `json:"method"`
		Params  struct {
			Name      string          `json:"name"`
			Arguments json.RawMessage `json:"arguments"`
		} `json:"params"`
	}
	if err := json.Unmarshal(body, &req); err == nil {
		// Check if this is a tools/call for a gateway tool.
		if req.Method == "tools/call" && gatewayToolNames[req.Params.Name] {
			resp := p.handleGatewayTool(req.ID, req.Params.Name, req.Params.Arguments, r)
			w.Header().Set("Content-Type", "application/json")
			w.Write(resp)
			return
		}
	}

	// Forward to Chapel subprocess.
	resp, err := p.SendRequest(body)
	if err != nil {
		http.Error(w, "proxy error: "+err.Error(), http.StatusBadGateway)
		return
	}

	// Intercept tools/list responses to inject gateway tools.
	if isToolsListResponse(resp) {
		resp = injectGatewayTools(resp)
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(resp)
}

// handleGatewayTool dispatches a tool call to the gateway's local handlers.
func (p *MCPProxy) handleGatewayTool(id json.RawMessage, tool string, args json.RawMessage, r *http.Request) []byte {
	caller, _ := IdentityFromContext(r.Context())
	ctx := r.Context()

	var result json.RawMessage
	var err error

	switch tool {
	case "juggler_resolve_composite":
		result, err = handleResolveAsMCPTool(p.resolver, args)
		if p.audit != nil {
			var a struct{ Query string }
			json.Unmarshal(args, &a)
			p.audit.Log(AuditEntry{
				Caller:  caller,
				Action:  "resolve_composite",
				Query:   a.Query,
				Allowed: err == nil,
			})
		}

	case "juggler_setec_list":
		names, e := p.setec.List(ctx)
		if e != nil {
			err = e
		} else {
			result, _ = json.Marshal(map[string]any{
				"content": []map[string]any{{
					"type": "text",
					"text": mustMarshal(map[string]any{"secrets": names}),
				}},
			})
		}

	case "juggler_setec_get":
		var a struct{ Name string }
		json.Unmarshal(args, &a)
		val, e := p.setec.Get(ctx, a.Name)
		if e != nil {
			err = e
		} else {
			result, _ = json.Marshal(map[string]any{
				"content": []map[string]any{{
					"type": "text",
					"text": val,
				}},
			})
		}
		if p.audit != nil {
			p.audit.Log(AuditEntry{
				Caller:  caller,
				Action:  "setec_get",
				Query:   a.Name,
				Source:  "setec",
				Allowed: e == nil,
			})
		}

	case "juggler_setec_put":
		var a struct {
			Name  string
			Value string
		}
		json.Unmarshal(args, &a)
		e := p.setec.Put(ctx, a.Name, a.Value)
		if e != nil {
			err = e
		} else {
			result, _ = json.Marshal(map[string]any{
				"content": []map[string]any{{
					"type": "text",
					"text": fmt.Sprintf("stored secret %q in setec", a.Name),
				}},
			})
		}

	case "juggler_audit_log":
		var a struct{ Count int }
		json.Unmarshal(args, &a)
		if a.Count <= 0 {
			a.Count = 20
		}
		if a.Count > 100 {
			a.Count = 100
		}
		entries := p.audit.Recent(a.Count)
		result, _ = json.Marshal(map[string]any{
			"content": []map[string]any{{
				"type": "text",
				"text": mustMarshal(map[string]any{"entries": entries, "count": len(entries)}),
			}},
		})

	default:
		err = fmt.Errorf("unknown gateway tool: %s", tool)
	}

	if err != nil {
		resp, _ := json.Marshal(map[string]any{
			"jsonrpc": "2.0",
			"id":      id,
			"error":   map[string]any{"code": -32000, "message": err.Error()},
		})
		return resp
	}

	resp, _ := json.Marshal(map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"result":  result,
	})
	return resp
}

// HandleSSE handles GET /mcp/sse for Server-Sent Events.
func (p *MCPProxy) HandleSSE(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	ch := p.subscribe()
	defer p.unsubscribe(ch)

	for {
		select {
		case <-r.Context().Done():
			return
		case data := <-ch:
			fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()
		}
	}
}
