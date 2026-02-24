package main

import (
	"context"
	"encoding/json"
	"fmt"
)

// ApertureClient queries AI API usage metrics from the gateway's MeterStore.
// MeterStore aggregates both MCP-layer metrics (from proxy instrumentation)
// and LLM-layer metrics (from Aperture webhook events).
//
// Tailscale Aperture has no REST API for usage queries -- all data flows
// through the webhook receiver and S3 export ingester into MeterStore.
type ApertureClient struct {
	baseURL    string
	meterStore *MeterStore
}

// NewApertureClient creates a client for AI API usage metrics.
// The baseURL is used only for the Configured() check (indicating Aperture
// is deployed on the tailnet). All metrics come from MeterStore.
func NewApertureClient(baseURL string) *ApertureClient {
	return &ApertureClient{
		baseURL: baseURL,
	}
}

// SetMeterStore wires the MeterStore into this client.
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

// QueryUsage returns usage metrics from MeterStore.
// MeterStore aggregates MCP tool call metrics recorded by the proxy and
// LLM call metrics received via the Aperture webhook receiver.
func (a *ApertureClient) QueryUsage(ctx context.Context, campaignID, agent string) (*ApertureUsage, error) {
	if !a.Configured() {
		return nil, fmt.Errorf("aperture not configured")
	}

	usage := &ApertureUsage{
		CampaignID: campaignID,
		Agent:      agent,
	}

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

	if usage.Source == "" {
		usage.Source = "none"
	}

	return usage, nil
}

// handleApertureUsageTool returns AI API usage metrics as an MCP tool response.
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
			"error":  "No MeterStore available. Ensure gateway metering is enabled.",
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
