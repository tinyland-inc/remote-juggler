package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestWebhookSingleEvent(t *testing.T) {
	receiver := NewApertureWebhookReceiver(100, nil)

	body, _ := json.Marshal(ApertureEvent{
		Type:      "llm_call",
		Agent:     "openclaw",
		Model:     "claude-sonnet-4",
		Tokens:    1500,
		Timestamp: time.Now(),
	})

	req := httptest.NewRequest(http.MethodPost, "/aperture/webhook", bytes.NewReader(body))
	w := httptest.NewRecorder()
	receiver.HandleWebhook(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}

	var resp map[string]any
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["accepted"].(float64) != 1 {
		t.Errorf("accepted = %v, want 1", resp["accepted"])
	}

	events := receiver.Recent(10)
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	if events[0].Type != "llm_call" {
		t.Errorf("type = %q, want 'llm_call'", events[0].Type)
	}
}

func TestWebhookBatchEvents(t *testing.T) {
	receiver := NewApertureWebhookReceiver(100, nil)

	events := []ApertureEvent{
		{Type: "llm_call", Agent: "openclaw", Tokens: 100, Timestamp: time.Now()},
		{Type: "llm_call", Agent: "hexstrike", Tokens: 200, Timestamp: time.Now()},
		{Type: "rate_limit", Agent: "openclaw", Timestamp: time.Now()},
	}
	body, _ := json.Marshal(events)

	req := httptest.NewRequest(http.MethodPost, "/aperture/webhook", bytes.NewReader(body))
	w := httptest.NewRecorder()
	receiver.HandleWebhook(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}

	var resp map[string]any
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["accepted"].(float64) != 3 {
		t.Errorf("accepted = %v, want 3", resp["accepted"])
	}

	if receiver.Count() != 3 {
		t.Errorf("count = %d, want 3", receiver.Count())
	}
}

func TestWebhookMalformedJSON(t *testing.T) {
	receiver := NewApertureWebhookReceiver(100, nil)

	req := httptest.NewRequest(http.MethodPost, "/aperture/webhook", bytes.NewReader([]byte("{invalid")))
	w := httptest.NewRecorder()
	receiver.HandleWebhook(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want 400", w.Code)
	}
}

func TestWebhookMethodNotAllowed(t *testing.T) {
	receiver := NewApertureWebhookReceiver(100, nil)

	req := httptest.NewRequest(http.MethodGet, "/aperture/webhook", nil)
	w := httptest.NewRecorder()
	receiver.HandleWebhook(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Errorf("status = %d, want 405", w.Code)
	}
}

func TestWebhookSkipsEventsWithoutType(t *testing.T) {
	receiver := NewApertureWebhookReceiver(100, nil)

	events := []ApertureEvent{
		{Type: "llm_call", Agent: "openclaw", Timestamp: time.Now()},
		{Type: "", Agent: "unknown", Timestamp: time.Now()}, // No type -- skip.
	}
	body, _ := json.Marshal(events)

	req := httptest.NewRequest(http.MethodPost, "/aperture/webhook", bytes.NewReader(body))
	w := httptest.NewRecorder()
	receiver.HandleWebhook(w, req)

	var resp map[string]any
	json.NewDecoder(w.Body).Decode(&resp)
	if resp["accepted"].(float64) != 1 {
		t.Errorf("accepted = %v, want 1", resp["accepted"])
	}
}

func TestWebhookRingBufferEviction(t *testing.T) {
	receiver := NewApertureWebhookReceiver(3, nil)

	for i := 0; i < 5; i++ {
		receiver.record(ApertureEvent{
			Type:      "llm_call",
			Agent:     "openclaw",
			Tokens:    i + 1,
			Timestamp: time.Now(),
		})
	}

	if receiver.Count() != 3 {
		t.Errorf("count = %d, want 3 (buffer size)", receiver.Count())
	}

	events := receiver.Recent(3)
	// Newest first: tokens should be 5, 4, 3.
	if events[0].Tokens != 5 {
		t.Errorf("newest event tokens = %d, want 5", events[0].Tokens)
	}
	if events[2].Tokens != 3 {
		t.Errorf("oldest event tokens = %d, want 3", events[2].Tokens)
	}
}

func TestWebhookMergesIntoMeterStore(t *testing.T) {
	store := NewMeterStore()
	receiver := NewApertureWebhookReceiver(100, store)

	receiver.record(ApertureEvent{
		Type:       "llm_call",
		Agent:      "openclaw",
		CampaignID: "oc-dep-audit",
		Model:      "claude-sonnet-4",
		DurationMs: 500,
		Timestamp:  time.Now(),
	})
	receiver.record(ApertureEvent{
		Type:       "llm_call",
		Agent:      "openclaw",
		CampaignID: "oc-dep-audit",
		Model:      "claude-sonnet-4",
		DurationMs: 300,
		Error:      "rate_limit",
		Timestamp:  time.Now(),
	})

	// Check MeterStore has the merged data.
	buckets := store.Query("openclaw", "oc-dep-audit")
	if len(buckets) != 1 {
		t.Fatalf("expected 1 bucket, got %d", len(buckets))
	}
	if buckets[0].ToolCalls != 2 {
		t.Errorf("ToolCalls = %d, want 2", buckets[0].ToolCalls)
	}
	if buckets[0].ErrorCount != 1 {
		t.Errorf("ErrorCount = %d, want 1", buckets[0].ErrorCount)
	}
	if buckets[0].TotalDurationMs != 800 {
		t.Errorf("TotalDurationMs = %d, want 800", buckets[0].TotalDurationMs)
	}
}

func TestWebhookMergesTokensIntoMeterStore(t *testing.T) {
	store := NewMeterStore()
	receiver := NewApertureWebhookReceiver(100, store)

	// Event with input/output tokens.
	receiver.record(ApertureEvent{
		Type:         "llm_call",
		Agent:        "openclaw",
		CampaignID:   "oc-smoketest",
		Model:        "claude-sonnet-4-20250514",
		InputTokens:  1200,
		OutputTokens: 350,
		Timestamp:    time.Now(),
	})
	// Event with legacy "tokens" field only.
	receiver.record(ApertureEvent{
		Type:       "llm_call",
		Agent:      "openclaw",
		CampaignID: "oc-smoketest",
		Model:      "claude-sonnet-4-20250514",
		Tokens:     500,
		Timestamp:  time.Now(),
	})

	buckets := store.Query("openclaw", "oc-smoketest")
	if len(buckets) != 1 {
		t.Fatalf("expected 1 bucket, got %d", len(buckets))
	}
	b := buckets[0]
	// First event: input=1200, output=350; second: legacy tokens=500 -> output=500
	if b.InputTokens != 1200 {
		t.Errorf("InputTokens = %d, want 1200", b.InputTokens)
	}
	if b.OutputTokens != 850 {
		t.Errorf("OutputTokens = %d, want 850 (350 + 500 legacy)", b.OutputTokens)
	}
}

func TestWebhookNonLLMEventNotMerged(t *testing.T) {
	store := NewMeterStore()
	receiver := NewApertureWebhookReceiver(100, store)

	receiver.record(ApertureEvent{
		Type:      "rate_limit",
		Agent:     "openclaw",
		Timestamp: time.Now(),
	})

	// Non-llm_call events should not create meter records.
	buckets := store.Query("openclaw", "")
	if len(buckets) != 0 {
		t.Errorf("expected 0 buckets for non-llm_call event, got %d", len(buckets))
	}
}

func TestWebhookRecentOrder(t *testing.T) {
	receiver := NewApertureWebhookReceiver(100, nil)

	for i := 0; i < 5; i++ {
		receiver.record(ApertureEvent{
			Type:      "llm_call",
			Tokens:    i + 1,
			Timestamp: time.Now(),
		})
	}

	events := receiver.Recent(3)
	if len(events) != 3 {
		t.Fatalf("expected 3 events, got %d", len(events))
	}
	// Newest first.
	if events[0].Tokens != 5 {
		t.Errorf("events[0].Tokens = %d, want 5", events[0].Tokens)
	}
	if events[1].Tokens != 4 {
		t.Errorf("events[1].Tokens = %d, want 4", events[1].Tokens)
	}
	if events[2].Tokens != 3 {
		t.Errorf("events[2].Tokens = %d, want 3", events[2].Tokens)
	}
}
