package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFetchGatewayTools(t *testing.T) {
	gateway := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"result": map[string]any{
				"tools": []map[string]any{
					{
						"name":        "juggler_status",
						"description": "Check RemoteJuggler status",
						"inputSchema": json.RawMessage(`{"type":"object","properties":{}}`),
					},
					{
						"name":        "juggler_keys_list",
						"description": "List KeePassXC entries",
						"inputSchema": json.RawMessage(`{"type":"object","properties":{"query":{"type":"string"}}}`),
					},
				},
			},
		})
	}))
	defer gateway.Close()

	tools, err := fetchGatewayTools(http.DefaultClient, gateway.URL)
	if err != nil {
		t.Fatalf("fetchGatewayTools error: %v", err)
	}
	if len(tools) != 2 {
		t.Fatalf("expected 2 tools, got %d", len(tools))
	}

	// Verify OpenAI function format.
	for _, tool := range tools {
		if tool["type"] != "function" {
			t.Errorf("tool type should be 'function', got %v", tool["type"])
		}
		fn, ok := tool["function"].(map[string]any)
		if !ok {
			t.Error("tool missing function field")
			continue
		}
		if fn["name"] == nil || fn["description"] == nil {
			t.Error("function missing name or description")
		}
	}
}

func TestFetchGatewayTools_EmptyResponse(t *testing.T) {
	gateway := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"result": map[string]any{
				"tools": []any{},
			},
		})
	}))
	defer gateway.Close()

	tools, err := fetchGatewayTools(http.DefaultClient, gateway.URL)
	if err != nil {
		t.Fatalf("fetchGatewayTools error: %v", err)
	}
	if len(tools) != 0 {
		t.Errorf("expected 0 tools, got %d", len(tools))
	}
}

func TestFetchGatewayTools_Unreachable(t *testing.T) {
	_, err := fetchGatewayTools(http.DefaultClient, "http://localhost:1")
	if err == nil {
		t.Fatal("expected error for unreachable gateway")
	}
}
