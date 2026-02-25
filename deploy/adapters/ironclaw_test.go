package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestIronclawBackend_Type(t *testing.T) {
	b := NewIronclawBackend("http://localhost:18789")
	if b.Type() != "ironclaw" {
		t.Errorf("expected ironclaw, got %s", b.Type())
	}
}

func TestIronclawBackend_Health(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/health" {
			json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
		}
	}))
	defer agent.Close()

	b := NewIronclawBackend(agent.URL)
	if err := b.Health(); err != nil {
		t.Fatalf("health error: %v", err)
	}
}

func TestIronclawBackend_HealthUnreachable(t *testing.T) {
	b := NewIronclawBackend("http://localhost:1")
	if err := b.Health(); err == nil {
		t.Fatal("expected error for unreachable agent")
	}
}

func TestIronclawBackend_Dispatch(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/chat" {
			json.NewEncoder(w).Encode(map[string]any{
				"message": map[string]string{"content": "analysis complete"},
				"tool_calls": []map[string]string{
					{"name": "juggler_status"},
					{"name": "juggler_keys_list"},
				},
			})
		}
	}))
	defer agent.Close()

	b := NewIronclawBackend(agent.URL)
	campaign := json.RawMessage(`{"id":"test","name":"test","process":["check health"],"tools":["juggler_status"]}`)

	result, err := b.Dispatch(campaign, "run-1")
	if err != nil {
		t.Fatalf("dispatch error: %v", err)
	}
	if result.Status != "success" {
		t.Errorf("expected success, got %s", result.Status)
	}
	if result.ToolCalls != 2 {
		t.Errorf("expected 2 tool calls, got %d", result.ToolCalls)
	}
}

func TestIronclawBackend_DispatchError(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		w.Write([]byte("internal error"))
	}))
	defer agent.Close()

	b := NewIronclawBackend(agent.URL)
	campaign := json.RawMessage(`{"id":"test","name":"test","process":["fail"],"tools":[]}`)

	result, err := b.Dispatch(campaign, "run-1")
	if err != nil {
		t.Fatalf("dispatch should not return error: %v", err)
	}
	if result.Status != "failure" {
		t.Errorf("expected failure, got %s", result.Status)
	}
}
