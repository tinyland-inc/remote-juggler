package main

import (
	"context"
	"encoding/json"
	"fmt"
)

// handleCampaignStatusTool returns aggregated campaign results from Setec.
// It queries keys matching the pattern remotejuggler/campaigns/{id}/latest.
func handleCampaignStatusTool(setec *SetecClient, params json.RawMessage) (json.RawMessage, error) {
	var args struct {
		CampaignID string `json:"campaign_id"`
	}
	if err := json.Unmarshal(params, &args); err != nil {
		return nil, fmt.Errorf("parse args: %w", err)
	}

	ctx := context.Background()

	if args.CampaignID != "" {
		// Return status for a specific campaign.
		key := "remotejuggler/campaigns/" + args.CampaignID + "/latest"
		val, err := setec.Get(ctx, key)
		if err != nil {
			return mcpTextResult(map[string]any{
				"campaign_id": args.CampaignID,
				"status":      "not_found",
				"error":       err.Error(),
			})
		}
		// Parse stored JSON result.
		var result map[string]any
		if err := json.Unmarshal([]byte(val), &result); err != nil {
			result = map[string]any{"raw": val}
		}
		result["campaign_id"] = args.CampaignID
		result["status"] = "found"
		return mcpTextResult(result)
	}

	// List all campaigns by checking for known prefixes.
	names, err := setec.List(ctx)
	if err != nil {
		return mcpTextResult(map[string]any{
			"error":  err.Error(),
			"status": "setec_unavailable",
		})
	}

	// Filter for campaign result keys.
	var campaigns []map[string]any
	prefix := "remotejuggler/campaigns/"
	suffix := "/latest"
	for _, name := range names {
		if len(name) > len(prefix)+len(suffix) &&
			name[:len(prefix)] == prefix &&
			name[len(name)-len(suffix):] == suffix {

			id := name[len(prefix) : len(name)-len(suffix)]
			val, err := setec.Get(ctx, name)
			entry := map[string]any{"campaign_id": id}
			if err != nil {
				entry["status"] = "error"
				entry["error"] = err.Error()
			} else {
				var result map[string]any
				if err := json.Unmarshal([]byte(val), &result); err != nil {
					entry["status"] = "stored"
					entry["raw"] = val
				} else {
					for k, v := range result {
						entry[k] = v
					}
					entry["status"] = "stored"
				}
			}
			campaigns = append(campaigns, entry)
		}
	}

	return mcpTextResult(map[string]any{
		"campaigns": campaigns,
		"count":     len(campaigns),
	})
}

// mcpTextResult wraps a value as an MCP tool response with text content.
func mcpTextResult(v any) (json.RawMessage, error) {
	content := []map[string]any{{
		"type": "text",
		"text": mustMarshal(v),
	}}
	resp := map[string]any{"content": content}
	return json.Marshal(resp)
}
