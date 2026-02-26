package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestPicoclawBackend_Type(t *testing.T) {
	b := NewPicoclawBackend("http://localhost:18790", "")
	if b.Type() != "picoclaw" {
		t.Errorf("expected picoclaw, got %s", b.Type())
	}
}

func TestPicoclawBackend_Health(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
		}
	}))
	defer agent.Close()

	b := NewPicoclawBackend(agent.URL, "")
	if err := b.Health(); err != nil {
		t.Fatalf("health error: %v", err)
	}
}

func TestPicoclawBackend_Dispatch(t *testing.T) {
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{
				{
					"message": map[string]any{
						"content":    "scan complete",
						"tool_calls": []any{},
					},
				},
			},
			"usage": map[string]int{"total_tokens": 150},
		})
	}))
	defer agent.Close()

	b := NewPicoclawBackend(agent.URL, "")
	campaign := json.RawMessage(`{"id":"test","name":"test","process":["scan"],"tools":[]}`)

	result, err := b.Dispatch(campaign, "run-1")
	if err != nil {
		t.Fatalf("dispatch error: %v", err)
	}
	if result.Status != "success" {
		t.Errorf("expected success, got %s", result.Status)
	}
	if v, ok := result.KPIs["total_tokens"]; !ok || v.(int) != 150 {
		t.Errorf("expected total_tokens=150, got %v", result.KPIs["total_tokens"])
	}
}

func TestPicoclawBackend_DispatchWithFindings(t *testing.T) {
	findingsJSON := `__findings__[{"title":"Dead code in utils.go","body":"Function unused","severity":"low","labels":["cleanup"],"fingerprint":"dead-code-utils-001"}]__end_findings__`

	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{
				{
					"message": map[string]any{
						"content":    "Scan complete.\n" + findingsJSON,
						"tool_calls": []any{},
					},
				},
			},
			"usage": map[string]int{"total_tokens": 200},
		})
	}))
	defer agent.Close()

	b := NewPicoclawBackend(agent.URL, "")
	campaign := json.RawMessage(`{"id":"oc-dead-code","name":"Dead Code","process":["scan"],"tools":[]}`)

	result, err := b.Dispatch(campaign, "run-p1")
	if err != nil {
		t.Fatalf("dispatch error: %v", err)
	}
	if result.Status != "success" {
		t.Errorf("expected success, got %s", result.Status)
	}
	if len(result.Findings) != 1 {
		t.Fatalf("expected 1 finding, got %d", len(result.Findings))
	}
	f := result.Findings[0]
	if f.Title != "Dead code in utils.go" {
		t.Errorf("unexpected title: %s", f.Title)
	}
	if f.CampaignID != "oc-dead-code" {
		t.Errorf("expected campaign_id=oc-dead-code, got %s", f.CampaignID)
	}
}

func TestPicoclawBackend_DispatchWithGatewayTools(t *testing.T) {
	// Mock gateway that returns tool list.
	gateway := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"result": map[string]any{
				"tools": []map[string]any{
					{"name": "juggler_status", "description": "check status"},
				},
			},
		})
	}))
	defer gateway.Close()

	// Mock agent.
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{
				{"message": map[string]any{"content": "done"}},
			},
			"usage": map[string]int{"total_tokens": 100},
		})
	}))
	defer agent.Close()

	b := NewPicoclawBackend(agent.URL, gateway.URL)
	campaign := json.RawMessage(`{"id":"test","name":"test","process":["check"],"tools":["juggler_status"]}`)

	result, err := b.Dispatch(campaign, "run-1")
	if err != nil {
		t.Fatalf("dispatch error: %v", err)
	}
	if result.Status != "success" {
		t.Errorf("expected success, got %s", result.Status)
	}
}
