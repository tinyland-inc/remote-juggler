package main

import "encoding/json"

// gatewayTools returns MCP tool definitions for tools the gateway injects
// on top of the Chapel subprocess's tools.
func gatewayTools() []json.RawMessage {
	tools := []map[string]any{
		{
			"name":        "juggler_resolve_composite",
			"description": "Resolve a secret from multiple sources (env, SOPS, KDBX, Setec) with configurable precedence. Returns the first match along with which sources were checked.",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"query": map[string]any{
						"type":        "string",
						"description": "The secret name or key to resolve (e.g. DATABASE_URL, github-token)",
					},
					"sources": map[string]any{
						"type":        "array",
						"items":       map[string]any{"type": "string", "enum": []string{"env", "sops", "kdbx", "setec"}},
						"description": "Sources to check, in precedence order. Defaults to gateway config precedence.",
					},
				},
				"required": []string{"query"},
			},
		},
		{
			"name":        "juggler_setec_list",
			"description": "List all secrets available in the Tailscale Setec secret store.",
			"inputSchema": map[string]any{
				"type":       "object",
				"properties": map[string]any{},
			},
		},
		{
			"name":        "juggler_setec_get",
			"description": "Get a secret value from the Tailscale Setec secret store by name.",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"name": map[string]any{
						"type":        "string",
						"description": "The secret name (without prefix)",
					},
				},
				"required": []string{"name"},
			},
		},
		{
			"name":        "juggler_setec_put",
			"description": "Store a secret in the Tailscale Setec secret store.",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"name": map[string]any{
						"type":        "string",
						"description": "The secret name (without prefix)",
					},
					"value": map[string]any{
						"type":        "string",
						"description": "The secret value to store",
					},
				},
				"required": []string{"name", "value"},
			},
		},
		{
			"name":        "juggler_audit_log",
			"description": "View recent credential access audit log entries. Each entry shows who accessed what, from which source, and whether it was allowed.",
			"inputSchema": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"count": map[string]any{
						"type":        "integer",
						"description": "Number of recent entries to return (default 20, max 100)",
					},
				},
			},
		},
	}

	var raw []json.RawMessage
	for _, t := range tools {
		b, _ := json.Marshal(t)
		raw = append(raw, b)
	}
	return raw
}

// injectGatewayTools modifies a tools/list JSON-RPC response to include
// the gateway's own tools alongside the Chapel subprocess's tools.
func injectGatewayTools(response []byte) []byte {
	var msg struct {
		JSONRPC string          `json:"jsonrpc"`
		ID      json.RawMessage `json:"id"`
		Result  struct {
			Tools []json.RawMessage `json:"tools"`
		} `json:"result"`
	}

	if err := json.Unmarshal(response, &msg); err != nil {
		return response // pass through on parse failure
	}

	// Append gateway tools.
	msg.Result.Tools = append(msg.Result.Tools, gatewayTools()...)

	modified, err := json.Marshal(msg)
	if err != nil {
		return response
	}
	return modified
}

// isToolsListResponse checks if a JSON-RPC response is for tools/list.
// We detect this by checking if the result has a "tools" array.
func isToolsListResponse(data []byte) bool {
	var msg struct {
		Result struct {
			Tools json.RawMessage `json:"tools"`
		} `json:"result"`
	}
	if err := json.Unmarshal(data, &msg); err != nil {
		return false
	}
	return msg.Result.Tools != nil
}
