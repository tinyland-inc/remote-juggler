package main

import (
	"context"
	"encoding/json"
	"testing"
	"time"
)

func TestNewApertureClientDefaults(t *testing.T) {
	client := NewApertureClient("http://ai")
	if !client.Configured() {
		t.Error("client with URL should be configured")
	}
}

func TestApertureClientNotConfigured(t *testing.T) {
	client := NewApertureClient("")
	if client.Configured() {
		t.Error("client without URL and without MeterStore should not be configured")
	}

	_, err := client.QueryUsage(nil, "", "")
	if err == nil {
		t.Error("expected error for unconfigured client")
	}
}

func TestApertureClientConfiguredWithMeterStore(t *testing.T) {
	client := NewApertureClient("")
	client.SetMeterStore(NewMeterStore())
	if !client.Configured() {
		t.Error("client with MeterStore should be configured")
	}
}

func TestHandleApertureUsageToolNotConfigured(t *testing.T) {
	params := json.RawMessage(`{}`)
	result, err := handleApertureUsageTool(nil, params)
	if err != nil {
		t.Fatalf("handleApertureUsageTool: %v", err)
	}

	var resp struct {
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(result, &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	var inner map[string]any
	if err := json.Unmarshal([]byte(resp.Content[0].Text), &inner); err != nil {
		t.Fatalf("inner JSON: %v", err)
	}
	if inner["status"] != "not_configured" {
		t.Errorf("status = %v, want 'not_configured'", inner["status"])
	}
}

func TestHandleApertureUsageToolInvalidParams(t *testing.T) {
	params := json.RawMessage(`{invalid`)
	_, err := handleApertureUsageTool(nil, params)
	if err == nil {
		t.Error("expected error for invalid params")
	}
}

func TestApertureClientQueryUsageFromMeterStore(t *testing.T) {
	store := NewMeterStore()
	now := time.Now()
	store.Record(MeterRecord{
		Agent:         "openclaw",
		CampaignID:    "oc-dep-audit",
		ToolName:      "juggler_setec_list",
		RequestBytes:  100,
		ResponseBytes: 500,
		DurationMs:    42,
		Timestamp:     now,
	})
	store.Record(MeterRecord{
		Agent:         "openclaw",
		CampaignID:    "oc-dep-audit",
		ToolName:      "juggler_audit_log",
		RequestBytes:  200,
		ResponseBytes: 300,
		DurationMs:    30,
		Timestamp:     now,
		IsError:       true,
	})

	client := NewApertureClient("")
	client.SetMeterStore(store)

	usage, err := client.QueryUsage(context.Background(), "oc-dep-audit", "openclaw")
	if err != nil {
		t.Fatalf("QueryUsage: %v", err)
	}
	if usage.MCPToolCalls != 2 {
		t.Errorf("MCPToolCalls = %d, want 2", usage.MCPToolCalls)
	}
	if usage.MCPRequestBytes != 300 {
		t.Errorf("MCPRequestBytes = %d, want 300", usage.MCPRequestBytes)
	}
	if usage.MCPResponseBytes != 800 {
		t.Errorf("MCPResponseBytes = %d, want 800", usage.MCPResponseBytes)
	}
	if usage.MCPErrorCount != 1 {
		t.Errorf("MCPErrorCount = %d, want 1", usage.MCPErrorCount)
	}
	if usage.TotalCalls != 2 {
		t.Errorf("TotalCalls = %d, want 2", usage.TotalCalls)
	}
	if usage.Source != "mcp_metering" {
		t.Errorf("Source = %q, want 'mcp_metering'", usage.Source)
	}
}

func TestApertureClientQueryUsageNoMeterStoreData(t *testing.T) {
	// Configured with URL only, no MeterStore -- should return source "none".
	client := NewApertureClient("http://ai")
	usage, err := client.QueryUsage(context.Background(), "", "")
	if err != nil {
		t.Fatalf("QueryUsage: %v", err)
	}
	if usage.Source != "none" {
		t.Errorf("Source = %q, want 'none'", usage.Source)
	}
	if usage.TotalCalls != 0 {
		t.Errorf("TotalCalls = %d, want 0", usage.TotalCalls)
	}
}

func TestApertureClientQueryUsageWithWebhookData(t *testing.T) {
	// Simulate webhook-merged LLM data in the same MeterStore.
	store := NewMeterStore()
	now := time.Now()

	// MCP-layer tool call.
	store.Record(MeterRecord{
		Agent:        "openclaw",
		CampaignID:   "oc-dep-audit",
		ToolName:     "juggler_setec_list",
		RequestBytes: 100,
		Timestamp:    now,
	})

	// LLM-layer call from webhook receiver (merged into same store).
	store.Record(MeterRecord{
		Agent:      "openclaw",
		CampaignID: "oc-dep-audit",
		ToolName:   "llm:claude-sonnet-4",
		DurationMs: 500,
		Timestamp:  now,
	})

	client := NewApertureClient("http://ai")
	client.SetMeterStore(store)

	usage, err := client.QueryUsage(context.Background(), "oc-dep-audit", "openclaw")
	if err != nil {
		t.Fatalf("QueryUsage: %v", err)
	}
	// Both MCP and webhook-merged LLM calls should be counted.
	if usage.MCPToolCalls != 2 {
		t.Errorf("MCPToolCalls = %d, want 2", usage.MCPToolCalls)
	}
	if usage.TotalCalls != 2 {
		t.Errorf("TotalCalls = %d, want 2", usage.TotalCalls)
	}
	if usage.Source != "mcp_metering" {
		t.Errorf("Source = %q, want 'mcp_metering'", usage.Source)
	}
}

func TestApertureClientQueryUsageTokenTracking(t *testing.T) {
	store := NewMeterStore()
	now := time.Now()

	// LLM calls with token data (from webhook/S3 ingestion).
	store.Record(MeterRecord{
		Agent:        "openclaw",
		CampaignID:   "oc-smoketest",
		ToolName:     "llm:claude-sonnet-4-20250514",
		InputTokens:  1200,
		OutputTokens: 350,
		DurationMs:   500,
		Timestamp:    now,
	})
	store.Record(MeterRecord{
		Agent:        "openclaw",
		CampaignID:   "oc-smoketest",
		ToolName:     "llm:claude-sonnet-4-20250514",
		InputTokens:  800,
		OutputTokens: 200,
		DurationMs:   400,
		Timestamp:    now.Add(time.Second),
	})

	client := NewApertureClient("")
	client.SetMeterStore(store)

	usage, err := client.QueryUsage(context.Background(), "oc-smoketest", "openclaw")
	if err != nil {
		t.Fatalf("QueryUsage: %v", err)
	}
	if usage.InputTokens != 2000 {
		t.Errorf("InputTokens = %d, want 2000", usage.InputTokens)
	}
	if usage.OutputTokens != 550 {
		t.Errorf("OutputTokens = %d, want 550", usage.OutputTokens)
	}
	if usage.TotalTokens != 2550 {
		t.Errorf("TotalTokens = %d, want 2550", usage.TotalTokens)
	}
	if usage.TotalCalls != 2 {
		t.Errorf("TotalCalls = %d, want 2", usage.TotalCalls)
	}
}

func TestHandleApertureUsageToolWithMeterStore(t *testing.T) {
	store := NewMeterStore()
	store.Record(MeterRecord{
		Agent:         "openclaw",
		CampaignID:    "oc-dep-audit",
		ToolName:      "juggler_setec_list",
		RequestBytes:  100,
		ResponseBytes: 500,
		Timestamp:     time.Now(),
	})

	client := NewApertureClient("")
	client.SetMeterStore(store)

	params := json.RawMessage(`{"campaign_id": "oc-dep-audit", "agent": "openclaw"}`)
	result, err := handleApertureUsageTool(client, params)
	if err != nil {
		t.Fatalf("handleApertureUsageTool: %v", err)
	}

	var resp struct {
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(result, &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	var inner map[string]any
	if err := json.Unmarshal([]byte(resp.Content[0].Text), &inner); err != nil {
		t.Fatalf("inner JSON: %v", err)
	}
	if inner["status"] != "ok" {
		t.Errorf("status = %v, want 'ok'", inner["status"])
	}
	if inner["source"] != "mcp_metering" {
		t.Errorf("source = %v, want 'mcp_metering'", inner["source"])
	}
	if inner["mcp_tool_calls"].(float64) != 1 {
		t.Errorf("mcp_tool_calls = %v, want 1", inner["mcp_tool_calls"])
	}
}
