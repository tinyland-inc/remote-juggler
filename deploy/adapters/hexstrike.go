package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// HexstrikeBackend translates campaign requests to HexStrike-AI's Flask API.
// HexStrike exposes security tools via a FastMCP-based server on port 8888.
// It also provides a Flask dashboard and REST API for tool execution.
type HexstrikeBackend struct {
	agentURL   string
	httpClient *http.Client
}

func NewHexstrikeBackend(agentURL string) *HexstrikeBackend {
	return &HexstrikeBackend{
		agentURL: agentURL,
		httpClient: &http.Client{
			Timeout: 10 * time.Minute,
		},
	}
}

func (b *HexstrikeBackend) Type() string { return "hexstrike-ai" }

func (b *HexstrikeBackend) Health() error {
	resp, err := b.httpClient.Get(b.agentURL + "/health")
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("hexstrike health: %d", resp.StatusCode)
	}
	return nil
}

// Dispatch sends a campaign to HexStrike via its tool execution API.
// HexStrike's MCP server exposes 150+ security tools. The adapter invokes
// tools sequentially based on the campaign's process steps.
func (b *HexstrikeBackend) Dispatch(campaign json.RawMessage, runID string) (*LastResult, error) {
	var c struct {
		ID      string   `json:"id"`
		Name    string   `json:"name"`
		Process []string `json:"process"`
		Tools   []string `json:"tools"`
		Targets []struct {
			Org  string `json:"org"`
			Repo string `json:"repo"`
		} `json:"targets"`
	}
	if err := json.Unmarshal(campaign, &c); err != nil {
		return nil, fmt.Errorf("parse campaign: %w", err)
	}

	var trace []ToolTrace
	var lastErr string

	// Execute each tool in the campaign via HexStrike's MCP endpoint.
	for _, toolName := range c.Tools {
		args := map[string]any{
			"campaign_id": c.ID,
			"run_id":      runID,
		}

		// Pass target repos if available.
		if len(c.Targets) > 0 {
			var repos []string
			for _, t := range c.Targets {
				repos = append(repos, fmt.Sprintf("%s/%s", t.Org, t.Repo))
			}
			args["targets"] = repos
		}

		result, err := b.callMCPTool(toolName, args)
		ts := time.Now().UTC().Format(time.RFC3339)

		if err != nil {
			trace = append(trace, ToolTrace{
				Timestamp: ts,
				Tool:      toolName,
				Summary:   fmt.Sprintf("error: %v", err),
				IsError:   true,
			})
			lastErr = err.Error()
			continue
		}

		trace = append(trace, ToolTrace{
			Timestamp: ts,
			Tool:      toolName,
			Summary:   truncate(string(result), 200),
		})
	}

	status := "success"
	if lastErr != "" {
		status = "failure"
	}

	return &LastResult{
		Status:    status,
		ToolCalls: len(trace),
		ToolTrace: trace,
		Error:     lastErr,
	}, nil
}

// callMCPTool calls a single tool on HexStrike's MCP server endpoint.
func (b *HexstrikeBackend) callMCPTool(toolName string, args map[string]any) (json.RawMessage, error) {
	payload := map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]any{
			"name":      toolName,
			"arguments": args,
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal: %w", err)
	}

	req, err := http.NewRequest(http.MethodPost, b.agentURL+"/mcp", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := b.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("hexstrike mcp: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("hexstrike returned %d: %s", resp.StatusCode, string(respBody))
	}

	var mcpResp struct {
		Result json.RawMessage `json:"result"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(respBody, &mcpResp); err != nil {
		return respBody, nil
	}
	if mcpResp.Error != nil {
		return nil, fmt.Errorf("mcp error: %s", mcpResp.Error.Message)
	}

	return mcpResp.Result, nil
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}
