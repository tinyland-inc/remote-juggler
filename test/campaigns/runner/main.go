// Campaign runner: orchestration controller for RemoteJuggler agent test campaigns.
//
// Runs as a sidecar in the OpenClaw pod. Reads campaign definitions from
// a mounted ConfigMap, evaluates triggers (cron, event, manual), and dispatches
// work to agents via rj-gateway MCP tool calls. Results are collected and
// stored in Setec.
//
// Usage:
//
//	campaign-runner [flags]
//	  --campaigns-dir  path to campaign definitions (default /etc/campaigns)
//	  --gateway-url    rj-gateway MCP endpoint (default https://rj-gateway:443)
//	  --once           run all due campaigns once and exit (for testing)
//	  --campaign       run a specific campaign by ID and exit
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"
)

func main() {
	campaignsDir := flag.String("campaigns-dir", envOrDefault("CAMPAIGNS_DIR", "/etc/campaigns"), "path to campaign definitions")
	gatewayURL := flag.String("gateway-url", envOrDefault("RJ_GATEWAY_URL", "https://rj-gateway:443"), "rj-gateway MCP endpoint")
	once := flag.Bool("once", false, "run all due campaigns once and exit")
	campaignID := flag.String("campaign", "", "run a specific campaign by ID and exit")
	interval := flag.Duration("interval", 60*time.Second, "scheduler check interval")
	apiPort := flag.Int("api-port", intEnvOrDefault("CAMPAIGN_RUNNER_API_PORT", 8081), "HTTP API server port (0 to disable)")
	flag.Parse()

	log.SetFlags(log.LstdFlags | log.Lmsgprefix)
	log.SetPrefix("campaign-runner: ")

	// Load campaign index.
	indexPath := filepath.Join(*campaignsDir, "index.json")
	index, err := LoadIndex(indexPath)
	if err != nil {
		log.Fatalf("load index: %v", err)
	}
	log.Printf("loaded %d campaigns from %s", len(index.Campaigns), indexPath)

	// Load all campaign definitions.
	registry := make(map[string]*Campaign)
	for id, entry := range index.Campaigns {
		if !entry.Enabled {
			log.Printf("campaign %s: disabled, skipping", id)
			continue
		}
		defPath := filepath.Join(*campaignsDir, entry.File)
		// Fallback: ConfigMap mounts files flat (no subdirectories),
		// but index.json references paths like "claude-code/cc-gateway-health.json".
		// Try the basename if the full path doesn't exist.
		if _, statErr := os.Stat(defPath); os.IsNotExist(statErr) {
			defPath = filepath.Join(*campaignsDir, filepath.Base(entry.File))
		}
		campaign, err := LoadCampaign(defPath)
		if err != nil {
			log.Printf("campaign %s: load error: %v", id, err)
			continue
		}
		if campaign.ID != id {
			log.Printf("campaign %s: ID mismatch (file says %s)", id, campaign.ID)
			continue
		}
		registry[id] = campaign
		log.Printf("campaign %s: loaded (%s, agent=%s)", id, campaign.Name, campaign.Agent)
	}

	dispatcher := NewDispatcher(*gatewayURL)
	collector := NewCollector(*gatewayURL)
	scheduler := NewScheduler(registry, dispatcher, collector)

	// Run a specific campaign and exit.
	if *campaignID != "" {
		campaign, ok := registry[*campaignID]
		if !ok {
			log.Fatalf("campaign %q not found in registry", *campaignID)
		}
		ctx, cancel := context.WithTimeout(context.Background(), parseDuration(campaign.Guardrails.MaxDuration))
		defer cancel()
		if err := scheduler.RunCampaign(ctx, campaign); err != nil {
			log.Fatalf("campaign %s failed: %v", *campaignID, err)
		}
		return
	}

	// Run all due campaigns once and exit.
	if *once {
		ctx := context.Background()
		scheduler.RunDue(ctx)
		return
	}

	// Start HTTP API server for manual triggering and status queries.
	if *apiPort > 0 {
		api := NewAPIServer(scheduler, registry)
		scheduler.OnResult = api.RecordResult
		go func() {
			addr := fmt.Sprintf(":%d", *apiPort)
			if err := api.ListenAndServe(addr); err != nil {
				log.Printf("api server error: %v", err)
			}
		}()
	}

	// Main loop: check for due campaigns on interval.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	done := make(chan os.Signal, 1)
	signal.Notify(done, syscall.SIGINT, syscall.SIGTERM)

	log.Printf("starting scheduler loop (interval=%s, %d campaigns)", *interval, len(registry))

	ticker := time.NewTicker(*interval)
	defer ticker.Stop()

	// Run immediately on start.
	scheduler.RunDue(ctx)

	for {
		select {
		case <-ticker.C:
			scheduler.RunDue(ctx)
		case <-done:
			log.Println("shutting down")
			cancel()
			return
		}
	}
}

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func intEnvOrDefault(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func parseDuration(s string) time.Duration {
	d, err := time.ParseDuration(s)
	if err != nil {
		return 30 * time.Minute // safe default
	}
	return d
}

// CampaignIndex is the registry of all campaigns.
type CampaignIndex struct {
	Version   string                   `json:"version"`
	Campaigns map[string]CampaignEntry `json:"campaigns"`
}

// CampaignEntry is a single entry in the campaign index.
type CampaignEntry struct {
	File       string  `json:"file"`
	Enabled    bool    `json:"enabled"`
	LastRun    *string `json:"lastRun"`
	LastResult *string `json:"lastResult"`
}

// LoadIndex loads the campaign index from a JSON file.
func LoadIndex(path string) (*CampaignIndex, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var index CampaignIndex
	if err := json.Unmarshal(data, &index); err != nil {
		return nil, err
	}
	return &index, nil
}
