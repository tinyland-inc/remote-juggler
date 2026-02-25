package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHexstrikeBackend_Type(t *testing.T) {
	b := NewHexstrikeBackend("http://localhost:8888")
	if b.Type() != "hexstrike-ai" {
		t.Errorf("expected hexstrike-ai, got %s", b.Type())
	}
}

func TestHexstrikeBackend_Health(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
		}
	}))
	defer agent.Close()

	b := NewHexstrikeBackend(agent.URL)
	if err := b.Health(); err != nil {
		t.Fatalf("health error: %v", err)
	}
}

func TestHexstrikeBackend_Dispatch(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/mcp" {
			json.NewEncoder(w).Encode(map[string]any{
				"result": map[string]any{
					"content": []map[string]string{
						{"type": "text", "text": "no credentials found"},
					},
				},
			})
		}
	}))
	defer agent.Close()

	b := NewHexstrikeBackend(agent.URL)
	campaign := json.RawMessage(`{
		"id": "hs-cred-exposure",
		"name": "Credential Exposure Scan",
		"process": ["scan repos"],
		"tools": ["credential_scan"],
		"targets": [{"forge":"github","org":"tinyland-inc","repo":"remote-juggler"}]
	}`)

	result, err := b.Dispatch(campaign, "run-1")
	if err != nil {
		t.Fatalf("dispatch error: %v", err)
	}
	if result.Status != "success" {
		t.Errorf("expected success, got %s: %s", result.Status, result.Error)
	}
	if result.ToolCalls != 1 {
		t.Errorf("expected 1 tool call, got %d", result.ToolCalls)
	}
}

func TestHexstrikeBackend_DispatchMCPError(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"error": map[string]any{
				"code":    -32600,
				"message": "tool not found",
			},
		})
	}))
	defer agent.Close()

	b := NewHexstrikeBackend(agent.URL)
	campaign := json.RawMessage(`{
		"id": "test",
		"name": "test",
		"process": ["scan"],
		"tools": ["nonexistent_tool"]
	}`)

	result, err := b.Dispatch(campaign, "run-1")
	if err != nil {
		t.Fatalf("dispatch should not return error: %v", err)
	}
	if result.Status != "failure" {
		t.Errorf("expected failure, got %s", result.Status)
	}
}

func TestTruncate(t *testing.T) {
	tests := []struct {
		input  string
		max    int
		expect string
	}{
		{"short", 10, "short"},
		{"this is a long string", 10, "this is..."},
		{"exact", 5, "exact"},
	}
	for _, tt := range tests {
		got := truncate(tt.input, tt.max)
		if got != tt.expect {
			t.Errorf("truncate(%q, %d) = %q, want %q", tt.input, tt.max, got, tt.expect)
		}
	}
}
