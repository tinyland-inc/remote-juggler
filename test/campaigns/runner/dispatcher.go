package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"sync/atomic"
	"time"
)

// Dispatcher sends MCP tool calls to agents via rj-gateway.
type Dispatcher struct {
	gatewayURL string
	httpClient *http.Client
}

// DispatchResult captures the outcome of dispatching a campaign to an agent.
type DispatchResult struct {
	ToolCalls int
	KPIs      map[string]any
	Error     string
}

// NewDispatcher creates a Dispatcher targeting the given rj-gateway URL.
func NewDispatcher(gatewayURL string) *Dispatcher {
	return &Dispatcher{
		gatewayURL: gatewayURL,
		httpClient: &http.Client{
			Timeout: 2 * time.Minute,
		},
	}
}

// Dispatch executes a campaign by calling the agent's tools via rj-gateway MCP.
// It calls each tool in the campaign's tools list sequentially, collecting results.
func (d *Dispatcher) Dispatch(ctx context.Context, campaign *Campaign, runID string) (*DispatchResult, error) {
	result := &DispatchResult{
		KPIs: make(map[string]any),
	}

	var toolCalls atomic.Int32

	// Execute each tool in the campaign's process via MCP.
	for _, toolName := range campaign.Tools {
		if ctx.Err() != nil {
			result.Error = fmt.Sprintf("context cancelled after %d tool calls", toolCalls.Load())
			break
		}

		resp, err := d.callTool(ctx, toolName, map[string]any{
			"_campaign_id": campaign.ID,
			"_run_id":      runID,
		})
		toolCalls.Add(1)

		if err != nil {
			log.Printf("campaign %s: tool %s error: %v", campaign.ID, toolName, err)
			// Continue with remaining tools unless context is done.
			continue
		}

		log.Printf("campaign %s: tool %s completed (response=%d bytes)",
			campaign.ID, toolName, len(resp))
	}

	result.ToolCalls = int(toolCalls.Load())
	return result, nil
}

// mcpRequest is a JSON-RPC 2.0 request for MCP tool calls.
type mcpRequest struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      int         `json:"id"`
	Method  string      `json:"method"`
	Params  mcpToolCall `json:"params"`
}

// mcpToolCall wraps a tool name and its arguments.
type mcpToolCall struct {
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments,omitempty"`
}

// mcpResponse is a JSON-RPC 2.0 response from rj-gateway.
type mcpResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      int             `json:"id"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *mcpError       `json:"error,omitempty"`
}

// mcpError represents a JSON-RPC error.
type mcpError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// callTool sends a single MCP tools/call request to rj-gateway.
func (d *Dispatcher) callTool(ctx context.Context, toolName string, args map[string]any) (json.RawMessage, error) {
	req := mcpRequest{
		JSONRPC: "2.0",
		ID:      1,
		Method:  "tools/call",
		Params: mcpToolCall{
			Name:      toolName,
			Arguments: args,
		},
	}

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, d.gatewayURL+"/mcp", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")

	resp, err := d.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("gateway returned %d: %s", resp.StatusCode, string(respBody))
	}

	var mcpResp mcpResponse
	if err := json.Unmarshal(respBody, &mcpResp); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w", err)
	}

	if mcpResp.Error != nil {
		return nil, fmt.Errorf("MCP error %d: %s", mcpResp.Error.Code, mcpResp.Error.Message)
	}

	return mcpResp.Result, nil
}
