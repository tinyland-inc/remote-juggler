package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// PicoclawBackend translates campaign requests to PicoClaw's native HTTP API.
// PicoClaw is a Go-based agent that exposes a model inference API on port 18790.
// Since PicoClaw lacks native MCP support (issue #290), the adapter's tool proxy
// registers rj-gateway tools in PicoClaw's native ToolRegistry format.
type PicoclawBackend struct {
	agentURL   string
	gatewayURL string
	httpClient *http.Client
}

func NewPicoclawBackend(agentURL, gatewayURL string) *PicoclawBackend {
	return &PicoclawBackend{
		agentURL:   agentURL,
		gatewayURL: gatewayURL,
		httpClient: &http.Client{
			Timeout: 5 * time.Minute,
		},
	}
}

func (b *PicoclawBackend) Type() string { return "picoclaw" }

func (b *PicoclawBackend) Health() error {
	resp, err := b.httpClient.Get(b.agentURL + "/health")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("picoclaw health: %d", resp.StatusCode)
	}
	return nil
}

// Dispatch sends a campaign to PicoClaw via its agent invocation API.
// PicoClaw accepts tasks via POST /v1/chat/completions (OpenAI-compatible).
func (b *PicoclawBackend) Dispatch(campaign json.RawMessage, runID string) (*LastResult, error) {
	var c struct {
		ID      string   `json:"id"`
		Name    string   `json:"name"`
		Process []string `json:"process"`
		Tools   []string `json:"tools"`
		Model   string   `json:"model"`
	}
	if err := json.Unmarshal(campaign, &c); err != nil {
		return nil, fmt.Errorf("parse campaign: %w", err)
	}

	// Build prompt from campaign process steps.
	prompt := fmt.Sprintf("Campaign: %s (run_id: %s)\n\n", c.Name, runID)
	for i, step := range c.Process {
		prompt += fmt.Sprintf("%d. %s\n", i+1, step)
	}

	// PicoClaw uses OpenAI-compatible chat completions API.
	payload := map[string]any{
		"model": c.Model,
		"messages": []map[string]string{
			{"role": "user", "content": prompt},
		},
		"stream": false,
	}

	// If gateway URL is configured, inject tool definitions via the proxy.
	if b.gatewayURL != "" {
		tools, err := fetchGatewayTools(b.httpClient, b.gatewayURL)
		if err == nil && len(tools) > 0 {
			payload["tools"] = tools
		}
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal payload: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, b.agentURL+"/v1/chat/completions", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := b.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("picoclaw chat: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return &LastResult{
			Status: "failure",
			Error:  fmt.Sprintf("picoclaw returned %d: %s", resp.StatusCode, string(respBody)),
		}, nil
	}

	// Parse OpenAI-compatible response.
	var chatResp struct {
		Choices []struct {
			Message struct {
				Content   string `json:"content"`
				ToolCalls []struct {
					Function struct {
						Name string `json:"name"`
					} `json:"function"`
				} `json:"tool_calls"`
			} `json:"message"`
		} `json:"choices"`
		Usage struct {
			TotalTokens int `json:"total_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return &LastResult{
			Status:    "success",
			ToolCalls: 0,
		}, nil
	}

	toolCalls := 0
	var trace []ToolTrace
	for _, choice := range chatResp.Choices {
		for _, tc := range choice.Message.ToolCalls {
			toolCalls++
			trace = append(trace, ToolTrace{
				Timestamp: time.Now().UTC().Format(time.RFC3339),
				Tool:      tc.Function.Name,
				Summary:   "executed via picoclaw",
			})
		}
	}

	return &LastResult{
		Status:    "success",
		ToolCalls: toolCalls,
		ToolTrace: trace,
		KPIs: map[string]any{
			"total_tokens": chatResp.Usage.TotalTokens,
		},
	}, nil
}
