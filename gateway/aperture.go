package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// ApertureClient queries the Aperture audit API for AI API usage metrics.
type ApertureClient struct {
	baseURL    string
	httpClient *http.Client
}

// NewApertureClient creates a client for the Aperture audit API.
// If httpClient is nil, a default client with 10s timeout is used.
func NewApertureClient(baseURL string, httpClient *http.Client) *ApertureClient {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 10 * time.Second}
	}
	return &ApertureClient{
		baseURL:    baseURL,
		httpClient: httpClient,
	}
}

// Configured returns whether the Aperture client has a base URL set.
func (a *ApertureClient) Configured() bool {
	return a.baseURL != ""
}

// ApertureUsage represents AI API usage for a campaign or agent.
type ApertureUsage struct {
	CampaignID  string `json:"campaign_id,omitempty"`
	Agent       string `json:"agent,omitempty"`
	TotalCalls  int    `json:"total_calls"`
	TotalTokens int    `json:"total_tokens"`
	Period      string `json:"period,omitempty"`
}

// QueryUsage queries Aperture for AI API usage, optionally filtered by campaign or agent.
func (a *ApertureClient) QueryUsage(ctx context.Context, campaignID, agent string) (*ApertureUsage, error) {
	if a.baseURL == "" {
		return nil, fmt.Errorf("aperture not configured")
	}

	url := a.baseURL + "/api/usage?"
	if campaignID != "" {
		url += "campaign_id=" + campaignID + "&"
	}
	if agent != "" {
		url += "agent=" + agent + "&"
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	resp, err := a.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("query aperture: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("aperture returned %d: %s", resp.StatusCode, string(body))
	}

	var usage ApertureUsage
	if err := json.Unmarshal(body, &usage); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}
	return &usage, nil
}

// handleApertureUsageTool returns AI API usage metrics from Aperture.
func handleApertureUsageTool(aperture *ApertureClient, params json.RawMessage) (json.RawMessage, error) {
	var args struct {
		CampaignID string `json:"campaign_id"`
		Agent      string `json:"agent"`
	}
	if err := json.Unmarshal(params, &args); err != nil {
		return nil, fmt.Errorf("parse args: %w", err)
	}

	if aperture == nil || !aperture.Configured() {
		return mcpTextResult(map[string]any{
			"status": "not_configured",
			"error":  "Aperture URL not configured. Set aperture_url in gateway config.",
		})
	}

	usage, err := aperture.QueryUsage(context.Background(), args.CampaignID, args.Agent)
	if err != nil {
		return mcpTextResult(map[string]any{
			"status": "error",
			"error":  err.Error(),
		})
	}

	return mcpTextResult(map[string]any{
		"status":       "ok",
		"campaign_id":  usage.CampaignID,
		"agent":        usage.Agent,
		"total_calls":  usage.TotalCalls,
		"total_tokens": usage.TotalTokens,
		"period":       usage.Period,
	})
}
