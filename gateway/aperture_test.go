package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestNewApertureClientDefaults(t *testing.T) {
	client := NewApertureClient("https://aperture.example.com", nil)
	if !client.Configured() {
		t.Error("client with URL should be configured")
	}
}

func TestApertureClientNotConfigured(t *testing.T) {
	client := NewApertureClient("", nil)
	if client.Configured() {
		t.Error("client without URL and without MeterStore should not be configured")
	}

	_, err := client.QueryUsage(nil, "", "")
	if err == nil {
		t.Error("expected error for unconfigured client")
	}
}

func TestApertureClientConfiguredWithMeterStore(t *testing.T) {
	client := NewApertureClient("", nil)
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

func TestApertureClientQueryUsageFromRemote(t *testing.T) {
	// Mock Aperture server.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/usage" {
			http.Error(w, "not found", 404)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(ApertureUsage{
			CampaignID:  r.URL.Query().Get("campaign_id"),
			Agent:       r.URL.Query().Get("agent"),
			TotalCalls:  42,
			TotalTokens: 12345,
			Period:      "24h",
		})
	}))
	defer server.Close()

	client := NewApertureClient(server.URL, nil)
	usage, err := client.QueryUsage(context.Background(), "oc-dep-audit", "openclaw")
	if err != nil {
		t.Fatalf("QueryUsage: %v", err)
	}
	if usage.TotalCalls != 42 {
		t.Errorf("TotalCalls = %d, want 42", usage.TotalCalls)
	}
	if usage.TotalTokens != 12345 {
		t.Errorf("TotalTokens = %d, want 12345", usage.TotalTokens)
	}
	if usage.Source != "aperture" {
		t.Errorf("Source = %q, want 'aperture'", usage.Source)
	}
}

func TestApertureClientQueryUsageServerError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "internal error", 500)
	}))
	defer server.Close()

	// With only remote (no meter store), query falls through to return
	// "none" source since remote fails but meterStore is nil.
	client := NewApertureClient(server.URL, nil)
	usage, err := client.QueryUsage(context.Background(), "", "")
	if err != nil {
		t.Fatalf("QueryUsage: %v", err)
	}
	if usage.Source != "none" {
		t.Errorf("Source = %q, want 'none'", usage.Source)
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

	client := NewApertureClient("", nil)
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

func TestApertureClientQueryUsageCombined(t *testing.T) {
	// Mock Aperture server.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(ApertureUsage{
			TotalCalls:  10,
			TotalTokens: 5000,
			Period:      "1h",
		})
	}))
	defer server.Close()

	store := NewMeterStore()
	store.Record(MeterRecord{
		Agent:        "openclaw",
		ToolName:     "juggler_setec_list",
		RequestBytes: 100,
		Timestamp:    time.Now(),
	})

	client := NewApertureClient(server.URL, nil)
	client.SetMeterStore(store)

	usage, err := client.QueryUsage(context.Background(), "", "openclaw")
	if err != nil {
		t.Fatalf("QueryUsage: %v", err)
	}
	if usage.Source != "combined" {
		t.Errorf("Source = %q, want 'combined'", usage.Source)
	}
	// MCP layer: 1 call; remote: 10 calls -> total 11.
	if usage.TotalCalls != 11 {
		t.Errorf("TotalCalls = %d, want 11", usage.TotalCalls)
	}
	if usage.TotalTokens != 5000 {
		t.Errorf("TotalTokens = %d, want 5000", usage.TotalTokens)
	}
	if usage.MCPToolCalls != 1 {
		t.Errorf("MCPToolCalls = %d, want 1", usage.MCPToolCalls)
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

	client := NewApertureClient("", nil)
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
