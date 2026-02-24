package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"sync"
	"time"
)

// ApertureWebhookReceiver handles real-time usage events from Aperture webhooks.
// Events are parsed and stored in a ring buffer, and optionally merged into
// the MeterStore for combined MCP + LLM metrics.
type ApertureWebhookReceiver struct {
	mu      sync.Mutex
	events  []ApertureEvent
	maxSize int
	meter   *MeterStore
}

// ApertureEvent represents a single event from an Aperture webhook.
// Uses json.RawMessage for resilience to alpha API changes.
type ApertureEvent struct {
	Type         string          `json:"type"`
	Timestamp    time.Time       `json:"timestamp"`
	Agent        string          `json:"agent,omitempty"`
	CampaignID   string          `json:"campaign_id,omitempty"`
	Model        string          `json:"model,omitempty"`
	Tokens       int             `json:"tokens,omitempty"`
	InputTokens  int             `json:"input_tokens,omitempty"`
	OutputTokens int             `json:"output_tokens,omitempty"`
	DurationMs   int64           `json:"duration_ms,omitempty"`
	Error        string          `json:"error,omitempty"`
	Raw          json.RawMessage `json:"raw,omitempty"`
}

// NewApertureWebhookReceiver creates a webhook receiver with the given ring buffer size.
func NewApertureWebhookReceiver(maxSize int, meter *MeterStore) *ApertureWebhookReceiver {
	if maxSize <= 0 {
		maxSize = 1000
	}
	return &ApertureWebhookReceiver{
		events:  make([]ApertureEvent, 0, maxSize),
		maxSize: maxSize,
		meter:   meter,
	}
}

// HandleWebhook is the HTTP handler for POST /aperture/webhook.
func (r *ApertureWebhookReceiver) HandleWebhook(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(req.Body)
	if err != nil {
		http.Error(w, "read body: "+err.Error(), http.StatusBadRequest)
		return
	}

	// Try to parse as a single event or an array of events.
	var events []ApertureEvent

	// First try array.
	if err := json.Unmarshal(body, &events); err != nil {
		// Try single event.
		var single ApertureEvent
		if err := json.Unmarshal(body, &single); err != nil {
			http.Error(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
			return
		}
		single.Raw = body
		events = []ApertureEvent{single}
	} else {
		// Store raw for each event.
		for i := range events {
			events[i].Raw = body
		}
	}

	accepted := 0
	for _, event := range events {
		if event.Type == "" {
			continue // Skip events without a type.
		}
		if event.Timestamp.IsZero() {
			event.Timestamp = time.Now().UTC()
		}
		r.record(event)
		accepted++
	}

	log.Printf("aperture webhook: accepted %d/%d events", accepted, len(events))

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"accepted": accepted,
		"total":    len(events),
	})
}

// record adds an event to the ring buffer and optionally updates MeterStore.
func (r *ApertureWebhookReceiver) record(event ApertureEvent) {
	r.mu.Lock()
	defer r.mu.Unlock()

	// Ring buffer eviction.
	if len(r.events) >= r.maxSize {
		r.events = r.events[1:]
	}
	r.events = append(r.events, event)

	// Merge LLM-layer metrics into MeterStore if available.
	if r.meter != nil && event.Type == "llm_call" {
		r.meter.Record(MeterRecord{
			Agent:         event.Agent,
			CampaignID:    event.CampaignID,
			ToolName:      fmt.Sprintf("llm:%s", event.Model),
			RequestBytes:  0, // Not available from webhook.
			ResponseBytes: 0,
			DurationMs:    event.DurationMs,
			Timestamp:     event.Timestamp,
			IsError:       event.Error != "",
		})
	}
}

// Recent returns the last n events (newest first).
func (r *ApertureWebhookReceiver) Recent(n int) []ApertureEvent {
	r.mu.Lock()
	defer r.mu.Unlock()

	if n > len(r.events) {
		n = len(r.events)
	}

	result := make([]ApertureEvent, n)
	for i := 0; i < n; i++ {
		result[i] = r.events[len(r.events)-1-i]
	}
	return result
}

// Count returns the total number of events in the buffer.
func (r *ApertureWebhookReceiver) Count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.events)
}
