package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// ApertureClient queries AI API usage metrics.
// In Phase 1, metrics come from the gateway's MCP-layer MeterStore.
// In Phase 2, LLM-layer metrics from Aperture webhooks will be merged.
type ApertureClient struct {
	baseURL    string
	httpClient *http.Client
	meterStore *MeterStore
}

// NewApertureClient creates a client for AI API usage metrics.
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

// SetMeterStore wires the MCP-layer MeterStore into this client.
func (a *ApertureClient) SetMeterStore(m *MeterStore) {
	a.meterStore = m
}

// Configured returns whether the Aperture client has a base URL or MeterStore.
func (a *ApertureClient) Configured() bool {
	return a.baseURL != "" || a.meterStore != nil
}

// ApertureUsage represents AI API usage for a campaign or agent.
type ApertureUsage struct {
	CampaignID  string `json:"campaign_id,omitempty"`
	Agent       string `json:"agent,omitempty"`
	TotalCalls  int    `json:"total_calls"`
	TotalTokens int    `json:"total_tokens"`
	Period      string `json:"period,omitempty"`
	Source      string `json:"source,omitempty"`
	// MCP-layer fields from gateway metering.
	MCPToolCalls     int   `json:"mcp_tool_calls,omitempty"`
	MCPRequestBytes  int64 `json:"mcp_request_bytes,omitempty"`
	MCPResponseBytes int64 `json:"mcp_response_bytes,omitempty"`
	MCPErrorCount    int   `json:"mcp_error_count,omitempty"`
}

// QueryUsage returns combined usage metrics from MeterStore (MCP-layer)
// and optionally the remote Aperture API (LLM-layer).
func (a *ApertureClient) QueryUsage(ctx context.Context, campaignID, agent string) (*ApertureUsage, error) {
	if !a.Configured() {
		return nil, fmt.Errorf("aperture not configured")
	}

	usage := &ApertureUsage{
		CampaignID: campaignID,
		Agent:      agent,
	}

	// MCP-layer metrics from MeterStore.
	if a.meterStore != nil {
		buckets := a.meterStore.Query(agent, campaignID)
		for _, b := range buckets {
			usage.MCPToolCalls += b.ToolCalls
			usage.MCPRequestBytes += b.RequestBytes
			usage.MCPResponseBytes += b.ResponseBytes
			usage.MCPErrorCount += b.ErrorCount
		}
		usage.TotalCalls = usage.MCPToolCalls
		usage.Source = "mcp_metering"
	}

	// LLM-layer metrics from remote Aperture API (Phase 2).
	if a.baseURL != "" {
		llmUsage, err := a.queryRemote(ctx, campaignID, agent)
		if err == nil {
			usage.TotalCalls += llmUsage.TotalCalls
			usage.TotalTokens = llmUsage.TotalTokens
			usage.Period = llmUsage.Period
			if usage.Source == "" {
				usage.Source = "aperture"
			} else {
				usage.Source = "combined"
			}
		}
		// Non-fatal: if Aperture is unreachable, return MCP-layer data.
	}

	if usage.Source == "" {
		usage.Source = "none"
	}

	return usage, nil
}

// queryRemote queries the remote Aperture API for LLM-layer metrics.
func (a *ApertureClient) queryRemote(ctx context.Context, campaignID, agent string) (*ApertureUsage, error) {
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

// handleApertureUsageTool returns AI API usage metrics from MeterStore + Aperture.
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
			"error":  "Aperture URL not configured and no MeterStore available. Set aperture_url in gateway config.",
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
		"status":             "ok",
		"source":             usage.Source,
		"campaign_id":        usage.CampaignID,
		"agent":              usage.Agent,
		"total_calls":        usage.TotalCalls,
		"total_tokens":       usage.TotalTokens,
		"period":             usage.Period,
		"mcp_tool_calls":     usage.MCPToolCalls,
		"mcp_request_bytes":  usage.MCPRequestBytes,
		"mcp_response_bytes": usage.MCPResponseBytes,
		"mcp_error_count":    usage.MCPErrorCount,
	})
}
