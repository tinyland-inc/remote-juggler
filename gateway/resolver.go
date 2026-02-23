package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
)

// ResolveResult is the response for a composite secret resolution.
type ResolveResult struct {
	Value          string   `json:"value,omitempty"`
	Source         string   `json:"source"`
	SourcesChecked []string `json:"sources_checked"`
	Cached         bool     `json:"cached"`
	Error          string   `json:"error,omitempty"`
}

// Resolver performs additive multi-source credential resolution.
type Resolver struct {
	proxy      *MCPProxy
	setec      *SetecClient
	precedence []string
}

// NewResolver creates a resolver with the given source precedence.
func NewResolver(proxy *MCPProxy, setec *SetecClient, precedence []string) *Resolver {
	return &Resolver{
		proxy:      proxy,
		setec:      setec,
		precedence: precedence,
	}
}

// Resolve queries sources in precedence order and returns the first match.
func (r *Resolver) Resolve(ctx context.Context, query string, sources []string) ResolveResult {
	if len(sources) == 0 {
		sources = r.precedence
	}

	result := ResolveResult{
		SourcesChecked: make([]string, 0, len(sources)),
	}

	for _, src := range sources {
		result.SourcesChecked = append(result.SourcesChecked, src)

		val, err := r.resolveSource(ctx, src, query)
		if err == nil && val != "" {
			result.Value = val
			result.Source = src
			return result
		}
	}

	result.Error = fmt.Sprintf("secret %q not found in any source", query)
	return result
}

// resolveSource queries a single source for a secret.
func (r *Resolver) resolveSource(ctx context.Context, source, query string) (string, error) {
	switch source {
	case "env":
		return r.resolveEnv(query)
	case "sops":
		return r.resolveSOPS(ctx, query)
	case "kdbx":
		return r.resolveKDBX(ctx, query)
	case "setec":
		return r.resolveSetec(ctx, query)
	default:
		return "", fmt.Errorf("unknown source: %s", source)
	}
}

// resolveEnv checks environment variables.
func (r *Resolver) resolveEnv(query string) (string, error) {
	val, ok := os.LookupEnv(query)
	if !ok {
		return "", fmt.Errorf("env %q not set", query)
	}
	return val, nil
}

// resolveSOPS queries the Chapel MCP subprocess for SOPS-decrypted values.
func (r *Resolver) resolveSOPS(ctx context.Context, query string) (string, error) {
	_ = ctx
	req := map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "juggler_keys_sops_export",
			"arguments": map[string]any{
				"query": query,
			},
		},
	}
	reqBytes, _ := json.Marshal(req)

	resp, err := r.proxy.SendRequest(reqBytes)
	if err != nil {
		return "", fmt.Errorf("sops query: %w", err)
	}

	var result map[string]json.RawMessage
	if err := json.Unmarshal(resp, &result); err != nil {
		return "", fmt.Errorf("sops parse: %w", err)
	}

	// Check for error in response.
	if errField, ok := result["error"]; ok {
		return "", fmt.Errorf("sops error: %s", string(errField))
	}

	// Extract value from result.
	if resultField, ok := result["result"]; ok {
		var toolResult struct {
			Content []struct {
				Text string `json:"text"`
			} `json:"content"`
		}
		if err := json.Unmarshal(resultField, &toolResult); err == nil && len(toolResult.Content) > 0 {
			return toolResult.Content[0].Text, nil
		}
	}

	return "", fmt.Errorf("sops: no result for %q", query)
}

// resolveKDBX queries the Chapel MCP subprocess for KeePassXC entries.
func (r *Resolver) resolveKDBX(ctx context.Context, query string) (string, error) {
	_ = ctx
	req := map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "juggler_keys_resolve",
			"arguments": map[string]any{
				"query": query,
			},
		},
	}
	reqBytes, _ := json.Marshal(req)

	resp, err := r.proxy.SendRequest(reqBytes)
	if err != nil {
		return "", fmt.Errorf("kdbx query: %w", err)
	}

	var result map[string]json.RawMessage
	if err := json.Unmarshal(resp, &result); err != nil {
		return "", fmt.Errorf("kdbx parse: %w", err)
	}

	if errField, ok := result["error"]; ok {
		return "", fmt.Errorf("kdbx error: %s", string(errField))
	}

	if resultField, ok := result["result"]; ok {
		var toolResult struct {
			Content []struct {
				Text string `json:"text"`
			} `json:"content"`
		}
		if err := json.Unmarshal(resultField, &toolResult); err == nil && len(toolResult.Content) > 0 {
			return toolResult.Content[0].Text, nil
		}
	}

	return "", fmt.Errorf("kdbx: no result for %q", query)
}

// resolveSetec queries the Setec server on the tailnet.
func (r *Resolver) resolveSetec(ctx context.Context, query string) (string, error) {
	return r.setec.Get(ctx, query)
}
