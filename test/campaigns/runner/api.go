package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
)

// APIServer provides HTTP endpoints for campaign management.
// Runs alongside the scheduler in the campaign runner sidecar.
type APIServer struct {
	scheduler *Scheduler
	registry  map[string]*Campaign

	mu          sync.Mutex
	lastResults map[string]*CampaignResult
}

// NewAPIServer creates an API server for the given scheduler and campaign registry.
func NewAPIServer(scheduler *Scheduler, registry map[string]*Campaign) *APIServer {
	return &APIServer{
		scheduler:   scheduler,
		registry:    registry,
		lastResults: make(map[string]*CampaignResult),
	}
}

// ListenAndServe starts the HTTP server on the given address.
func (a *APIServer) ListenAndServe(addr string) error {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", a.handleHealth)
	mux.HandleFunc("/trigger", a.handleTrigger)
	mux.HandleFunc("/status", a.handleStatus)
	mux.HandleFunc("/campaigns", a.handleCampaigns)

	log.Printf("api server listening on %s", addr)
	return http.ListenAndServe(addr, mux)
}

// RecordResult stores a campaign result for the /status endpoint.
func (a *APIServer) RecordResult(result *CampaignResult) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.lastResults[result.CampaignID] = result
}

// handleHealth returns runner health and loaded campaign count.
func (a *APIServer) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"status":         "ok",
		"service":        "campaign-runner",
		"campaign_count": len(a.registry),
	})
}

// handleTrigger manually triggers a campaign by ID.
// POST /trigger?campaign=ID
func (a *APIServer) handleTrigger(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	campaignID := r.URL.Query().Get("campaign")
	if campaignID == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "missing 'campaign' query parameter"})
		return
	}

	campaign, ok := a.registry[campaignID]
	if !ok {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "campaign not found", "campaign_id": campaignID})
		return
	}

	// Run asynchronously so the HTTP request returns immediately.
	// Use a detached context with the campaign's max duration as timeout,
	// since the request context will be canceled when the handler returns.
	go func() {
		timeout := parseDuration(campaign.Guardrails.MaxDuration)
		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		defer cancel()
		log.Printf("api: manual trigger for campaign %s (timeout=%s)", campaignID, timeout)
		if err := a.scheduler.RunCampaign(ctx, campaign); err != nil {
			log.Printf("api: campaign %s failed: %v", campaignID, err)
		}
	}()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]string{
		"status":      "accepted",
		"campaign_id": campaignID,
	})
}

// handleStatus returns campaign results.
// GET /status?campaign=ID (optional filter)
func (a *APIServer) handleStatus(w http.ResponseWriter, r *http.Request) {
	a.mu.Lock()
	defer a.mu.Unlock()

	campaignID := r.URL.Query().Get("campaign")

	w.Header().Set("Content-Type", "application/json")

	if campaignID != "" {
		result, ok := a.lastResults[campaignID]
		if !ok {
			json.NewEncoder(w).Encode(map[string]any{
				"campaign_id": campaignID,
				"status":      "no_runs",
			})
			return
		}
		json.NewEncoder(w).Encode(result)
		return
	}

	// Return all results.
	json.NewEncoder(w).Encode(map[string]any{
		"results": a.lastResults,
		"count":   len(a.lastResults),
	})
}

// handleCampaigns lists all loaded campaigns.
func (a *APIServer) handleCampaigns(w http.ResponseWriter, r *http.Request) {
	type campaignInfo struct {
		ID          string `json:"id"`
		Name        string `json:"name"`
		Agent       string `json:"agent"`
		Schedule    string `json:"schedule,omitempty"`
		MaxDuration string `json:"max_duration"`
	}

	campaigns := make([]campaignInfo, 0, len(a.registry))
	for _, c := range a.registry {
		campaigns = append(campaigns, campaignInfo{
			ID:          c.ID,
			Name:        c.Name,
			Agent:       c.Agent,
			Schedule:    c.Trigger.Schedule,
			MaxDuration: c.Guardrails.MaxDuration,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"campaigns": campaigns,
		"count":     len(campaigns),
	})
}
