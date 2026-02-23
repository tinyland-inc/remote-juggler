package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"tailscale.com/tsnet"
)

func main() {
	configPath := flag.String("config", "", "path to gateway config JSON")
	chapelBin := flag.String("chapel-bin", "", "path to remote-juggler binary (overrides config)")
	listen := flag.String("listen", "", "listen address (overrides config); use 'local' to skip tsnet")
	flag.Parse()

	cfg, err := LoadConfig(*configPath)
	if err != nil && *configPath != "" {
		log.Fatalf("load config: %v", err)
	}

	if *chapelBin != "" {
		cfg.ChapelBinary = *chapelBin
	}
	if *listen != "" {
		cfg.Listen = *listen
	}

	// Start MCP subprocess proxy.
	proxy := NewMCPProxy(cfg.ChapelBinary)
	if err := proxy.Start(); err != nil {
		log.Fatalf("start mcp proxy: %v", err)
	}
	defer proxy.Stop()

	// Initialize Setec client.
	// When running on tsnet, we'll replace the HTTP client with a tailnet-routed one.
	var setecHTTPClient *http.Client
	var tsnetServer *tsnet.Server

	// Determine if we should use tsnet or plain local listener.
	useTsnet := cfg.Listen != "local" && os.Getenv("RJ_GATEWAY_LOCAL") == ""

	if useTsnet {
		tsnetServer = &tsnet.Server{
			Hostname: cfg.Tailscale.Hostname,
		}
		if cfg.Tailscale.StateDir != "" {
			tsnetServer.Dir = cfg.Tailscale.StateDir
		}
		if err := tsnetServer.Start(); err != nil {
			log.Fatalf("tsnet start: %v", err)
		}
		defer tsnetServer.Close()

		// Use tsnet's HTTP client so Setec requests route through the tailnet.
		setecHTTPClient = tsnetServer.HTTPClient()
		log.Printf("joined tailnet as %s", cfg.Tailscale.Hostname)
	}

	setec := NewSetecClient(cfg.SetecURL, cfg.SetecPrefix, setecHTTPClient)
	audit := NewAuditLog()
	resolver := NewResolver(proxy, setec, cfg.Precedence)

	// Wire gateway tool handlers into the proxy for MCP tool interception.
	proxy.resolver = resolver
	proxy.setec = setec
	proxy.audit = audit

	// Start background polling for configured secrets.
	if setec.Configured() && len(cfg.SetecSecrets) > 0 {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		setec.StartPolling(ctx, cfg.SetecSecrets)
		log.Printf("polling %d secrets from setec at %s", len(cfg.SetecSecrets), cfg.SetecURL)
	}

	// Build handler chain.
	mux := http.NewServeMux()
	mux.HandleFunc("/mcp", proxy.HandleRPC)
	mux.HandleFunc("/mcp/sse", proxy.HandleSSE)
	mux.HandleFunc("/health", handleHealth)
	mux.HandleFunc("/resolve", handleResolve(resolver, audit))
	mux.HandleFunc("/audit", handleAuditQuery(audit))
	mux.HandleFunc("/setec/list", handleSetecList(setec))
	mux.HandleFunc("/setec/get", handleSetecGet(setec, audit))

	// Wrap with identity extraction middleware.
	handler := IdentityMiddleware(mux)

	// Get listener.
	var ln net.Listener
	if useTsnet && tsnetServer != nil {
		// Listen on the tailnet with TLS.
		ln, err = tsnetServer.ListenTLS("tcp", cfg.Listen)
		if err != nil {
			log.Fatalf("tsnet listen: %v", err)
		}
		log.Printf("rj-gateway listening on tailnet %s%s", cfg.Tailscale.Hostname, cfg.Listen)
	} else {
		// Local mode for development/testing.
		ln, err = net.Listen("tcp", cfg.Listen)
		if err != nil {
			log.Fatalf("listen: %v", err)
		}
		log.Printf("rj-gateway listening locally on %s", cfg.Listen)
	}

	server := &http.Server{
		Handler:      handler,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 60 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	// Graceful shutdown.
	done := make(chan os.Signal, 1)
	signal.Notify(done, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if err := server.Serve(ln); err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	<-done
	log.Println("shutting down...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	server.Shutdown(ctx)
	setec.StopPolling()
}

// handleHealth returns gateway status including Setec and tsnet connectivity.
func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "ok",
		"service": "rj-gateway",
		"version": "2.1.0",
	})
}

// handleResolve handles the composite secret resolution endpoint.
func handleResolve(resolver *Resolver, audit *AuditLog) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "read body: "+err.Error(), http.StatusBadRequest)
			return
		}

		var req struct {
			Query   string   `json:"query"`
			Sources []string `json:"sources"`
		}
		if err := json.Unmarshal(body, &req); err != nil {
			http.Error(w, "parse body: "+err.Error(), http.StatusBadRequest)
			return
		}

		if req.Query == "" {
			http.Error(w, `missing "query" field`, http.StatusBadRequest)
			return
		}

		caller, _ := IdentityFromContext(r.Context())
		result := resolver.Resolve(r.Context(), req.Query, req.Sources)

		// Audit log the access.
		audit.Log(AuditEntry{
			Caller:  caller,
			Action:  "resolve_composite",
			Query:   req.Query,
			Source:  result.Source,
			Allowed: result.Error == "",
			Reason:  result.Error,
		})

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(result)
	}
}

// handleAuditQuery returns recent audit log entries (for the Aperture dashboard).
func handleAuditQuery(audit *AuditLog) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		entries := audit.Recent(50)
		json.NewEncoder(w).Encode(map[string]any{
			"entries": entries,
			"count":   len(entries),
		})
	}
}

// handleSetecList lists available secrets in Setec.
func handleSetecList(setec *SetecClient) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		names, err := setec.List(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"secrets": names})
	}
}

// handleSetecGet retrieves a single secret from Setec.
func handleSetecGet(setec *SetecClient, audit *AuditLog) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var req struct {
			Name string `json:"name"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "parse: "+err.Error(), http.StatusBadRequest)
			return
		}

		caller, _ := IdentityFromContext(r.Context())

		val, err := setec.Get(r.Context(), req.Name)
		if err != nil {
			audit.Log(AuditEntry{
				Caller:  caller,
				Action:  "setec_get",
				Query:   req.Name,
				Allowed: false,
				Reason:  err.Error(),
			})
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}

		audit.Log(AuditEntry{
			Caller:  caller,
			Action:  "setec_get",
			Query:   req.Name,
			Source:  "setec",
			Allowed: true,
		})

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"value": val})
	}
}

// handleResolveAsMCPTool wraps the resolver as a JSON-RPC MCP tool response.
func handleResolveAsMCPTool(resolver *Resolver, params json.RawMessage) (json.RawMessage, error) {
	var args struct {
		Query   string   `json:"query"`
		Sources []string `json:"sources"`
	}
	if err := json.Unmarshal(params, &args); err != nil {
		return nil, fmt.Errorf("parse args: %w", err)
	}

	result := resolver.Resolve(context.Background(), args.Query, args.Sources)

	content := []map[string]any{{
		"type": "text",
		"text": mustMarshal(result),
	}}
	resp := map[string]any{"content": content}
	return json.Marshal(resp)
}

func mustMarshal(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}
