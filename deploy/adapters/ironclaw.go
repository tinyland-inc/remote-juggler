package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// IronclawBackend translates campaign requests to OpenClaw's native WebSocket/HTTP API.
// OpenClaw exposes a conversation API on port 18789 and an agent API on port 18790.
type IronclawBackend struct {
	agentURL   string
	httpClient *http.Client
}

func NewIronclawBackend(agentURL string) *IronclawBackend {
	return &IronclawBackend{
		agentURL: agentURL,
		httpClient: &http.Client{
			Timeout: 10 * time.Minute,
		},
	}
}

func (b *IronclawBackend) Type() string { return "ironclaw" }

func (b *IronclawBackend) Health() error {
	resp, err := b.httpClient.Get(b.agentURL + "/api/health")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("ironclaw health: %d", resp.StatusCode)
	}
	return nil
}

// Dispatch sends a campaign to IronClaw via its conversation API.
// IronClaw accepts messages via POST /api/chat with a conversation payload.
// The campaign's process steps are concatenated into a system+user message pair.
func (b *IronclawBackend) Dispatch(campaign json.RawMessage, runID string) (*LastResult, error) {
	// Parse campaign to extract process steps and tools.
	var c struct {
		ID      string   `json:"id"`
		Name    string   `json:"name"`
		Process []string `json:"process"`
		Tools   []string `json:"tools"`
		Mode    string   `json:"mode"`
		Model   string   `json:"model"`
	}
	if err := json.Unmarshal(campaign, &c); err != nil {
		return nil, fmt.Errorf("parse campaign: %w", err)
	}

	// Build the prompt from campaign process steps.
	prompt := fmt.Sprintf("Campaign: %s (run_id: %s)\n\n", c.Name, runID)
	for i, step := range c.Process {
		prompt += fmt.Sprintf("%d. %s\n", i+1, step)
	}
	if len(c.Tools) > 0 {
		prompt += fmt.Sprintf("\nAvailable MCP tools: %v\n", c.Tools)
	}

	// IronClaw conversation payload.
	payload := map[string]any{
		"messages": []map[string]string{
			{"role": "user", "content": prompt},
		},
		"stream": false,
	}
	if c.Model != "" {
		payload["model"] = c.Model
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal payload: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, b.agentURL+"/api/chat", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := b.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("ironclaw chat: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return &LastResult{
			Status: "failure",
			Error:  fmt.Sprintf("ironclaw returned %d: %s", resp.StatusCode, string(respBody)),
		}, nil
	}

	// Parse IronClaw response to extract tool usage stats.
	var chatResp struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
		ToolCalls []struct {
			Name string `json:"name"`
		} `json:"tool_calls"`
	}
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		// Non-fatal: we still got a response, just can't parse tool calls.
		return &LastResult{
			Status:    "success",
			ToolCalls: 0,
		}, nil
	}

	// Build tool trace from response.
	var trace []ToolTrace
	for _, tc := range chatResp.ToolCalls {
		trace = append(trace, ToolTrace{
			Timestamp: time.Now().UTC().Format(time.RFC3339),
			Tool:      tc.Name,
			Summary:   "executed via ironclaw",
		})
	}

	return &LastResult{
		Status:    "success",
		ToolCalls: len(chatResp.ToolCalls),
		ToolTrace: trace,
	}, nil
}
