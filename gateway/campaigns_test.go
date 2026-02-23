package main

import (
	"encoding/json"
	"testing"
)

func TestMCPTextResult(t *testing.T) {
	data := map[string]any{"status": "ok", "count": 3}
	result, err := mcpTextResult(data)
	if err != nil {
		t.Fatalf("mcpTextResult: %v", err)
	}

	var resp struct {
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(result, &resp); err != nil {
		t.Fatalf("unmarshal result: %v", err)
	}

	if len(resp.Content) != 1 {
		t.Fatalf("content length = %d, want 1", len(resp.Content))
	}
	if resp.Content[0].Type != "text" {
		t.Errorf("content type = %q, want 'text'", resp.Content[0].Type)
	}
	// Verify the text is valid JSON containing our data.
	var inner map[string]any
	if err := json.Unmarshal([]byte(resp.Content[0].Text), &inner); err != nil {
		t.Fatalf("inner text not valid JSON: %v", err)
	}
	if inner["status"] != "ok" {
		t.Errorf("inner status = %v, want 'ok'", inner["status"])
	}
}

func TestHandleCampaignStatusToolNoSetec(t *testing.T) {
	// With nil Setec client, should return setec_unavailable for list.
	setec := NewSetecClient("", "", nil)
	params := json.RawMessage(`{}`)
	result, err := handleCampaignStatusTool(setec, params)
	if err != nil {
		t.Fatalf("handleCampaignStatusTool: %v", err)
	}

	var resp struct {
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(result, &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(resp.Content) == 0 {
		t.Fatal("empty content")
	}

	var inner map[string]any
	if err := json.Unmarshal([]byte(resp.Content[0].Text), &inner); err != nil {
		t.Fatalf("inner JSON: %v", err)
	}
	// Unconfigured Setec should return an error status.
	if inner["status"] != "setec_unavailable" {
		t.Errorf("status = %v, want 'setec_unavailable'", inner["status"])
	}
}

func TestHandleCampaignStatusToolSpecificID(t *testing.T) {
	// Querying a specific campaign with unconfigured Setec should return not_found.
	setec := NewSetecClient("", "", nil)
	params := json.RawMessage(`{"campaign_id": "oc-dep-audit"}`)
	result, err := handleCampaignStatusTool(setec, params)
	if err != nil {
		t.Fatalf("handleCampaignStatusTool: %v", err)
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
	if inner["campaign_id"] != "oc-dep-audit" {
		t.Errorf("campaign_id = %v, want 'oc-dep-audit'", inner["campaign_id"])
	}
	if inner["status"] != "not_found" {
		t.Errorf("status = %v, want 'not_found'", inner["status"])
	}
}

func TestHandleCampaignStatusToolInvalidParams(t *testing.T) {
	setec := NewSetecClient("", "", nil)
	params := json.RawMessage(`{invalid`)
	_, err := handleCampaignStatusTool(setec, params)
	if err == nil {
		t.Error("expected error for invalid params")
	}
}
