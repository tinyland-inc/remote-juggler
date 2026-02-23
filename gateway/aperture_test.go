package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
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
		t.Error("client without URL should not be configured")
	}

	_, err := client.QueryUsage(nil, "", "")
	if err == nil {
		t.Error("expected error for unconfigured client")
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

func TestApertureClientQueryUsage(t *testing.T) {
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
}

func TestApertureClientQueryUsageServerError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "internal error", 500)
	}))
	defer server.Close()

	client := NewApertureClient(server.URL, nil)
	_, err := client.QueryUsage(context.Background(), "", "")
	if err == nil {
		t.Error("expected error for server error")
	}
}
