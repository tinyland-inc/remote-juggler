package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

// SetecClient provides access to secrets stored in a Tailscale Setec server.
// It implements background polling and local caching for resilience.
type SetecClient struct {
	baseURL    string
	prefix     string
	httpClient *http.Client

	mu    sync.RWMutex
	cache map[string]cachedSecret

	// pollInterval controls how often secrets are refreshed.
	pollInterval time.Duration
	// stopPoll cancels the background polling goroutine.
	stopPoll context.CancelFunc
}

type cachedSecret struct {
	value     string
	version   int
	fetchedAt time.Time
}

const defaultPollInterval = 5 * time.Minute

// NewSetecClient creates a client for the given Setec server URL.
// prefix is prepended to all secret names (e.g. "remotejuggler/").
// httpClient may be nil for default; pass a tsnet-aware client for tailnet routing.
func NewSetecClient(baseURL, prefix string, httpClient *http.Client) *SetecClient {
	if httpClient == nil {
		httpClient = http.DefaultClient
	}
	return &SetecClient{
		baseURL:      strings.TrimRight(baseURL, "/"),
		prefix:       prefix,
		httpClient:   httpClient,
		cache:        make(map[string]cachedSecret),
		pollInterval: defaultPollInterval,
	}
}

// Configured returns true if the Setec URL is set.
func (c *SetecClient) Configured() bool {
	return c.baseURL != ""
}

// StartPolling begins background secret refresh. Call with the list of
// secret names (without prefix) to keep warm.
func (c *SetecClient) StartPolling(ctx context.Context, secrets []string) {
	if !c.Configured() || len(secrets) == 0 {
		return
	}

	ctx, cancel := context.WithCancel(ctx)
	c.stopPoll = cancel

	go func() {
		// Initial fetch.
		for _, name := range secrets {
			c.Get(ctx, name) //nolint:errcheck
		}

		ticker := time.NewTicker(c.pollInterval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				for _, name := range secrets {
					c.Get(ctx, name) //nolint:errcheck
				}
			}
		}
	}()
}

// StopPolling stops the background refresh.
func (c *SetecClient) StopPolling() {
	if c.stopPoll != nil {
		c.stopPoll()
	}
}

// Get retrieves a secret by name (without prefix). Uses cache if fresh.
func (c *SetecClient) Get(ctx context.Context, name string) (string, error) {
	if !c.Configured() {
		return "", fmt.Errorf("setec not configured")
	}

	fullName := c.prefix + name

	// Check cache.
	c.mu.RLock()
	if cached, ok := c.cache[fullName]; ok && time.Since(cached.fetchedAt) < c.pollInterval {
		c.mu.RUnlock()
		return cached.value, nil
	}
	c.mu.RUnlock()

	// POST /api/get with {"name": "..."}
	body, _ := json.Marshal(map[string]string{"name": fullName})
	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/api/get", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Sec-X-Tailscale-No-Browsers", "setec")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("setec get %q: %w", name, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("setec get %q: status %d: %s", name, resp.StatusCode, string(respBody))
	}

	var result struct {
		Value   string `json:"Value"`
		Version int    `json:"Version"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("setec decode: %w", err)
	}

	// Setec returns base64-encoded values.
	decoded, err := base64.StdEncoding.DecodeString(result.Value)
	if err != nil {
		// If it's not base64, use raw value.
		decoded = []byte(result.Value)
	}

	value := string(decoded)

	// Update cache.
	c.mu.Lock()
	c.cache[fullName] = cachedSecret{
		value:     value,
		version:   result.Version,
		fetchedAt: time.Now(),
	}
	c.mu.Unlock()

	return value, nil
}

// List returns all secret names (without prefix) available in Setec.
func (c *SetecClient) List(ctx context.Context) ([]string, error) {
	if !c.Configured() {
		return nil, fmt.Errorf("setec not configured")
	}

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/api/list", nil)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Sec-X-Tailscale-No-Browsers", "setec")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("setec list: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("setec list: status %d: %s", resp.StatusCode, string(respBody))
	}

	var result struct {
		Secrets []struct {
			Name string `json:"Name"`
		} `json:"Secrets"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("setec decode: %w", err)
	}

	var names []string
	for _, s := range result.Secrets {
		name := strings.TrimPrefix(s.Name, c.prefix)
		names = append(names, name)
	}
	return names, nil
}

// Put stores a secret in Setec.
func (c *SetecClient) Put(ctx context.Context, name, value string) error {
	if !c.Configured() {
		return fmt.Errorf("setec not configured")
	}

	fullName := c.prefix + name
	encoded := base64.StdEncoding.EncodeToString([]byte(value))

	body, _ := json.Marshal(map[string]string{
		"name":  fullName,
		"value": encoded,
	})

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/api/put", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Sec-X-Tailscale-No-Browsers", "setec")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("setec put %q: %w", name, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("setec put %q: status %d: %s", name, resp.StatusCode, string(respBody))
	}

	// Update cache with new value.
	c.mu.Lock()
	c.cache[fullName] = cachedSecret{value: value, fetchedAt: time.Now()}
	c.mu.Unlock()

	return nil
}

// Info returns metadata about a secret (version, active status).
func (c *SetecClient) Info(ctx context.Context, name string) (map[string]any, error) {
	if !c.Configured() {
		return nil, fmt.Errorf("setec not configured")
	}

	fullName := c.prefix + name
	body, _ := json.Marshal(map[string]string{"name": fullName})

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/api/info", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Sec-X-Tailscale-No-Browsers", "setec")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("setec info %q: %w", name, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("setec info %q: status %d: %s", name, resp.StatusCode, string(respBody))
	}

	var info map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return nil, fmt.Errorf("setec decode: %w", err)
	}
	return info, nil
}
