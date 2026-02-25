package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNewAdapter_UnknownType(t *testing.T) {
	_, err := NewAdapter("unknown", "http://localhost:1234", "")
	if err == nil {
		t.Fatal("expected error for unknown agent type")
	}
}

func TestNewAdapter_ValidTypes(t *testing.T) {
	types := []string{"ironclaw", "openclaw", "picoclaw", "hexstrike-ai", "hexstrike"}
	for _, typ := range types {
		a, err := NewAdapter(typ, "http://localhost:1234", "http://gw:8080")
		if err != nil {
			t.Errorf("NewAdapter(%q) error: %v", typ, err)
		}
		if a == nil {
			t.Errorf("NewAdapter(%q) returned nil", typ)
		}
	}
}

func TestAdapter_Health(t *testing.T) {
	// Mock agent that returns healthy.
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/health" || r.URL.Path == "/health" {
			w.WriteHeader(http.StatusOK)
			json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
		}
	}))
	defer agent.Close()

	adapter, err := NewAdapter("ironclaw", agent.URL, "")
	if err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()
	adapter.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("health returned %d", w.Code)
	}

	var resp HealthResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	if resp.AgentType != "ironclaw" {
		t.Errorf("expected agent_type=ironclaw, got %s", resp.AgentType)
	}
	if resp.Scaffold {
		t.Error("scaffold should be false")
	}
}

func TestAdapter_StatusIdle(t *testing.T) {
	adapter, err := NewAdapter("ironclaw", "http://localhost:1234", "")
	if err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodGet, "/status", nil)
	w := httptest.NewRecorder()
	adapter.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status returned %d", w.Code)
	}

	var resp StatusResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	if resp.Status != "idle" {
		t.Errorf("expected idle status, got %s", resp.Status)
	}
}

func TestAdapter_CampaignMethodNotAllowed(t *testing.T) {
	adapter, err := NewAdapter("ironclaw", "http://localhost:1234", "")
	if err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodGet, "/campaign", nil)
	w := httptest.NewRecorder()
	adapter.ServeHTTP(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("expected 405, got %d", w.Code)
	}
}

func TestAdapter_CampaignInvalidBody(t *testing.T) {
	adapter, err := NewAdapter("ironclaw", "http://localhost:1234", "")
	if err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodPost, "/campaign", strings.NewReader("not json"))
	w := httptest.NewRecorder()
	adapter.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestAdapter_CampaignAccepted(t *testing.T) {
	// Mock agent that accepts and completes.
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/health":
			json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
		case "/api/chat":
			json.NewEncoder(w).Encode(map[string]any{
				"message":    map[string]string{"content": "done"},
				"tool_calls": []any{},
			})
		}
	}))
	defer agent.Close()

	adapter, err := NewAdapter("ironclaw", agent.URL, "")
	if err != nil {
		t.Fatal(err)
	}

	campaign := `{"id":"test","name":"test campaign","process":["step1"],"tools":["juggler_status"]}`
	body := `{"campaign":` + campaign + `,"run_id":"test-run-1"}`
	req := httptest.NewRequest(http.MethodPost, "/campaign", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	adapter.ServeHTTP(w, req)

	if w.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d: %s", w.Code, w.Body.String())
	}

	var resp CampaignResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatal(err)
	}
	if resp.Status != "accepted" {
		t.Errorf("expected status=accepted, got %s", resp.Status)
	}
}

func TestAdapter_CampaignConflict(t *testing.T) {
	adapter, err := NewAdapter("ironclaw", "http://localhost:1234", "")
	if err != nil {
		t.Fatal(err)
	}

	// Force running state.
	adapter.mu.Lock()
	adapter.status = "running"
	adapter.mu.Unlock()

	campaign := `{"campaign":{"id":"test"},"run_id":"test-run-2"}`
	req := httptest.NewRequest(http.MethodPost, "/campaign", strings.NewReader(campaign))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	adapter.ServeHTTP(w, req)

	if w.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", w.Code)
	}
}
