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
		if r.URL.Path == "/api/command" && r.Method == http.MethodPost {
			json.NewEncoder(w).Encode(map[string]any{
				"success":        true,
				"stdout":         "no credentials found in 15 files",
				"stderr":         "",
				"execution_time": 2.5,
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
	if result.ToolTrace[0].Summary != "no credentials found in 15 files" {
		t.Errorf("unexpected summary: %s", result.ToolTrace[0].Summary)
	}
}

func TestHexstrikeBackend_DispatchCommandError(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/command" {
			json.NewEncoder(w).Encode(map[string]any{
				"error": "command not found: nonexistent_tool",
			})
		}
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

func TestHexstrikeBackend_DispatchGatewayToolSkipped(t *testing.T) {
	// Gateway tools (juggler_*) should be skipped, not sent to HexStrike.
	b := NewHexstrikeBackend("http://localhost:1") // unreachable — should not be called
	campaign := json.RawMessage(`{
		"id": "test",
		"name": "test",
		"process": ["check audit"],
		"tools": ["juggler_audit_log"]
	}`)

	result, err := b.Dispatch(campaign, "run-1")
	if err != nil {
		t.Fatalf("dispatch error: %v", err)
	}
	if result.Status != "success" {
		t.Errorf("expected success for skipped gateway tool, got %s", result.Status)
	}
	if result.ToolTrace[0].Summary != "skipped (gateway tool)" {
		t.Errorf("unexpected summary: %s", result.ToolTrace[0].Summary)
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
