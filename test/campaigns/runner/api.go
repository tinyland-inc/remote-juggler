package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"path/filepath"
	"strings"
	"sync"
)

// APIServer provides HTTP endpoints for campaign management.
// Runs alongside the scheduler in the campaign runner sidecar.
type APIServer struct {
	scheduler *Scheduler
	registry  map[string]*Campaign

	// WebhookSecret is the HMAC-SHA256 secret for validating incoming
	// webhook payloads. When empty, HMAC validation is skipped.
	WebhookSecret string

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
	mux.HandleFunc("/webhook", a.handleWebhook)

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

// WebhookPayload is a normalized representation of forge push/PR events.
type WebhookPayload struct {
	// Event type: "push", "pull_request"
	Event string `json:"event"`
	// Forge: "github", "gitlab"
	Forge string `json:"forge"`
	// Ref is the full git ref (e.g. "refs/heads/main")
	Ref string `json:"ref"`
	// Repo is "org/repo"
	Repo string `json:"repo"`
	// ChangedFiles lists file paths modified in the push or PR.
	ChangedFiles []string `json:"changed_files,omitempty"`
}

// handleWebhook accepts GitHub/GitLab push/PR payloads and triggers matching campaigns.
// POST /webhook
func (a *APIServer) handleWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "read body: "+err.Error(), http.StatusBadRequest)
		return
	}

	// Validate HMAC if secret is configured.
	if a.WebhookSecret != "" {
		sig := r.Header.Get("X-Hub-Signature-256")
		if sig == "" {
			sig = r.Header.Get("X-Gitlab-Token")
		}
		if !validateHMAC(body, sig, a.WebhookSecret) {
			http.Error(w, "invalid signature", http.StatusForbidden)
			return
		}
	}

	var payload WebhookPayload
	if err := json.Unmarshal(body, &payload); err != nil {
		http.Error(w, "parse: "+err.Error(), http.StatusBadRequest)
		return
	}

	if payload.Event == "" {
		// Try to infer from GitHub event header.
		if gh := r.Header.Get("X-GitHub-Event"); gh != "" {
			payload.Event = gh
		}
	}

	if payload.Event == "" || payload.Repo == "" {
		http.Error(w, "missing event or repo", http.StatusBadRequest)
		return
	}

	triggered := a.matchWebhookToCampaigns(payload)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"triggered": triggered,
		"count":     len(triggered),
	})
}

// matchWebhookToCampaigns finds campaigns whose event triggers match the payload
// and dispatches them asynchronously.
func (a *APIServer) matchWebhookToCampaigns(payload WebhookPayload) []string {
	var triggered []string

	for id, campaign := range a.registry {
		trigger := campaign.Trigger

		// Check event type match.
		if trigger.Event != payload.Event {
			continue
		}

		// Check target repo match (any target matches).
		repoMatch := false
		for _, target := range campaign.Targets {
			targetRepo := target.Org + "/" + target.Repo
			if targetRepo == payload.Repo || target.Repo == "*" {
				repoMatch = true
				break
			}
		}
		if !repoMatch {
			continue
		}

		// Check path filters (if specified, at least one changed file must match).
		if len(trigger.PathFilters) > 0 && len(payload.ChangedFiles) > 0 {
			if !pathFiltersMatch(trigger.PathFilters, payload.ChangedFiles) {
				continue
			}
		}

		triggered = append(triggered, id)

		// Dispatch asynchronously.
		go func(c *Campaign, cID string) {
			timeout := parseDuration(c.Guardrails.MaxDuration)
			ctx, cancel := context.WithTimeout(context.Background(), timeout)
			defer cancel()
			log.Printf("api: webhook triggered campaign %s (event=%s, repo=%s)", cID, payload.Event, payload.Repo)
			if err := a.scheduler.RunCampaign(ctx, c); err != nil {
				log.Printf("api: webhook campaign %s failed: %v", cID, err)
			}
		}(campaign, id)
	}

	return triggered
}

// pathFiltersMatch checks if any changed file matches any of the glob patterns.
func pathFiltersMatch(filters []string, changedFiles []string) bool {
	for _, pattern := range filters {
		for _, file := range changedFiles {
			matched, err := filepath.Match(pattern, file)
			if err == nil && matched {
				return true
			}
			// Also try matching against just the filename for simple patterns.
			if matched, err := filepath.Match(pattern, filepath.Base(file)); err == nil && matched {
				return true
			}
		}
	}
	return false
}

// validateHMAC validates a GitHub-style HMAC-SHA256 signature.
// GitHub sends "sha256=<hex>", GitLab sends the raw token.
func validateHMAC(body []byte, signature, secret string) bool {
	if signature == "" {
		return false
	}

	// GitHub format: "sha256=<hex>"
	if strings.HasPrefix(signature, "sha256=") {
		sigHex := strings.TrimPrefix(signature, "sha256=")
		mac := hmac.New(sha256.New, []byte(secret))
		mac.Write(body)
		expected := hex.EncodeToString(mac.Sum(nil))
		return hmac.Equal([]byte(sigHex), []byte(expected))
	}

	// GitLab format: raw token comparison.
	return signature == secret
}
