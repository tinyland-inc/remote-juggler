package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

// ApertureS3Ingester polls an S3 bucket for Aperture usage export files
// and backfills the MeterStore for batch analysis. This provides historical
// data beyond what real-time webhooks capture.
type ApertureS3Ingester struct {
	bucket   string
	region   string
	prefix   string
	meter    *MeterStore
	client   *http.Client
	interval time.Duration

	// lastKey tracks the most recently processed S3 object key
	// to avoid reprocessing. Stored as simple string (not persistent
	// across restarts -- full history is in MeterStore/Setec).
	lastKey string
}

// S3Config holds S3 ingestion configuration.
type S3Config struct {
	Bucket string `json:"aperture_s3_bucket"`
	Region string `json:"aperture_s3_region"`
	Prefix string `json:"aperture_s3_prefix"`
}

// NewApertureS3Ingester creates an S3 ingester for Aperture usage exports.
func NewApertureS3Ingester(cfg S3Config, meter *MeterStore, client *http.Client) *ApertureS3Ingester {
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	return &ApertureS3Ingester{
		bucket:   cfg.Bucket,
		region:   cfg.Region,
		prefix:   cfg.Prefix,
		meter:    meter,
		client:   client,
		interval: 15 * time.Minute,
	}
}

// Configured returns whether the S3 ingester has required configuration.
func (s *ApertureS3Ingester) Configured() bool {
	return s.bucket != "" && s.region != ""
}

// Start begins the background polling loop. Returns a cancel function.
func (s *ApertureS3Ingester) Start(ctx context.Context) context.CancelFunc {
	ctx, cancel := context.WithCancel(ctx)
	go func() {
		if !s.Configured() {
			log.Printf("aperture-s3: not configured, skipping")
			return
		}
		log.Printf("aperture-s3: polling s3://%s/%s every %s", s.bucket, s.prefix, s.interval)

		ticker := time.NewTicker(s.interval)
		defer ticker.Stop()

		// Initial poll.
		s.poll(ctx)

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				s.poll(ctx)
			}
		}
	}()
	return cancel
}

// ApertureS3Record represents a single record from an Aperture S3 export file.
type ApertureS3Record struct {
	Timestamp    time.Time `json:"timestamp"`
	Agent        string    `json:"agent"`
	CampaignID   string    `json:"campaign_id"`
	Model        string    `json:"model"`
	InputTokens  int       `json:"input_tokens"`
	OutputTokens int       `json:"output_tokens"`
	DurationMs   int64     `json:"duration_ms"`
	Error        string    `json:"error"`
}

// poll fetches new export files from S3 and ingests them into the MeterStore.
func (s *ApertureS3Ingester) poll(ctx context.Context) {
	// Build S3 list URL. Uses virtual-hosted style for AWS compatibility.
	listURL := fmt.Sprintf("https://%s.s3.%s.amazonaws.com/?list-type=2&prefix=%s&start-after=%s",
		s.bucket, s.region, s.prefix, s.lastKey)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, listURL, nil)
	if err != nil {
		log.Printf("aperture-s3: list request error: %v", err)
		return
	}

	resp, err := s.client.Do(req)
	if err != nil {
		log.Printf("aperture-s3: list error: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		log.Printf("aperture-s3: list returned %d: %s", resp.StatusCode, string(body))
		return
	}

	// Parse S3 list response (simplified -- real implementation would use XML parser).
	// For now, this is a placeholder that processes newline-delimited JSON files.
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("aperture-s3: read list response: %v", err)
		return
	}

	keys := parseS3Keys(body)
	for _, key := range keys {
		if err := s.ingestKey(ctx, key); err != nil {
			log.Printf("aperture-s3: ingest %s: %v", key, err)
			continue
		}
		s.lastKey = key
	}

	if len(keys) > 0 {
		log.Printf("aperture-s3: ingested %d export files", len(keys))
	}
}

// ingestKey downloads and processes a single S3 export file.
func (s *ApertureS3Ingester) ingestKey(ctx context.Context, key string) error {
	getURL := fmt.Sprintf("https://%s.s3.%s.amazonaws.com/%s",
		s.bucket, s.region, key)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, getURL, nil)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}

	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("fetch: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("S3 returned %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read body: %w", err)
	}

	// Parse newline-delimited JSON records.
	var records []ApertureS3Record
	if err := json.Unmarshal(body, &records); err != nil {
		// Try as single record.
		var single ApertureS3Record
		if err := json.Unmarshal(body, &single); err != nil {
			return fmt.Errorf("parse records: %w", err)
		}
		records = []ApertureS3Record{single}
	}

	for _, rec := range records {
		s.meter.Record(MeterRecord{
			Agent:      rec.Agent,
			CampaignID: rec.CampaignID,
			ToolName:   fmt.Sprintf("llm:%s", rec.Model),
			DurationMs: rec.DurationMs,
			Timestamp:  rec.Timestamp,
			IsError:    rec.Error != "",
		})
	}

	return nil
}

// parseS3Keys is a placeholder that extracts object keys from an S3 list response.
// In production, this would parse the XML ListBucketResult.
func parseS3Keys(body []byte) []string {
	// Simplified: look for Key elements in the response.
	// Real implementation would use encoding/xml.
	var result struct {
		Contents []struct {
			Key string `json:"Key"`
		} `json:"Contents"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil
	}
	keys := make([]string, len(result.Contents))
	for i, c := range result.Contents {
		keys[i] = c.Key
	}
	return keys
}
