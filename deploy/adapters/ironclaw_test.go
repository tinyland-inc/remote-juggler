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
		if r.URL.Path == "/v1/chat/completions" && r.Method == http.MethodPost {
			json.NewEncoder(w).Encode(map[string]any{
				"choices": []map[string]any{
					{"message": map[string]string{"role": "assistant", "content": "pong"}},
				},
			})
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

func TestIronclawBackend_HealthAcceptsUnauthorized(t *testing.T) {
	// 401 means the server is up but auth is wrong — still healthy.
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer agent.Close()

	b := NewIronclawBackend(agent.URL)
	if err := b.Health(); err != nil {
		t.Fatalf("expected healthy on 401, got: %v", err)
	}
}

func TestIronclawBackend_Dispatch(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/responses" {
			json.NewEncoder(w).Encode(map[string]any{
				"id":     "resp_123",
				"status": "completed",
				"output": []map[string]any{
					{
						"type":      "function_call",
						"id":        "call_1",
						"name":      "juggler_status",
						"arguments": `{"query":"health"}`,
					},
					{
						"type":      "function_call",
						"id":        "call_2",
						"name":      "juggler_keys_list",
						"arguments": `{}`,
					},
					{
						"type": "message",
						"role": "assistant",
						"content": []map[string]any{
							{"type": "output_text", "text": "analysis complete"},
						},
					},
				},
				"usage": map[string]int{
					"input_tokens":  100,
					"output_tokens": 50,
					"total_tokens":  150,
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

func TestIronclawBackend_DispatchAuth(t *testing.T) {
	var gotAuth string
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		json.NewEncoder(w).Encode(map[string]any{
			"id": "resp_1", "status": "completed", "output": []any{},
		})
	}))
	defer agent.Close()

	b := NewIronclawBackend(agent.URL)
	b.SetAuthToken("test-token-123")
	campaign := json.RawMessage(`{"id":"test","name":"test","process":["ping"],"tools":[]}`)

	_, err := b.Dispatch(campaign, "run-1")
	if err != nil {
		t.Fatalf("dispatch error: %v", err)
	}
	if gotAuth != "Bearer test-token-123" {
		t.Errorf("expected Bearer auth header, got %q", gotAuth)
	}
}
