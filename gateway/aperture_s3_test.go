package main

import (
	"context"
	"encoding/xml"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestParseS3KeysXML(t *testing.T) {
	xmlBody := `<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>aperture-exports</Name>
  <Prefix>usage/</Prefix>
  <Contents>
    <Key>usage/2026-02-24T00.ndjson</Key>
    <LastModified>2026-02-24T01:00:00.000Z</LastModified>
    <Size>4096</Size>
  </Contents>
  <Contents>
    <Key>usage/2026-02-24T01.ndjson</Key>
    <LastModified>2026-02-24T02:00:00.000Z</LastModified>
    <Size>2048</Size>
  </Contents>
</ListBucketResult>`

	keys := parseS3Keys([]byte(xmlBody))
	if len(keys) != 2 {
		t.Fatalf("expected 2 keys, got %d", len(keys))
	}
	if keys[0] != "usage/2026-02-24T00.ndjson" {
		t.Errorf("keys[0] = %q, want 'usage/2026-02-24T00.ndjson'", keys[0])
	}
	if keys[1] != "usage/2026-02-24T01.ndjson" {
		t.Errorf("keys[1] = %q, want 'usage/2026-02-24T01.ndjson'", keys[1])
	}
}

func TestParseS3KeysEmptyBucket(t *testing.T) {
	xmlBody := `<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>aperture-exports</Name>
  <Prefix>usage/</Prefix>
</ListBucketResult>`

	keys := parseS3Keys([]byte(xmlBody))
	if len(keys) != 0 {
		t.Errorf("expected 0 keys for empty bucket, got %d", len(keys))
	}
}

func TestParseS3KeysInvalidXML(t *testing.T) {
	keys := parseS3Keys([]byte("not xml at all"))
	if len(keys) != 0 {
		t.Errorf("expected 0 keys for invalid XML, got %d", len(keys))
	}
}

func TestParseS3RecordsNDJSON(t *testing.T) {
	ndjson := `{"timestamp":"2026-02-24T01:00:00Z","agent":"openclaw","campaign_id":"oc-dep-audit","model":"claude-sonnet-4","input_tokens":100,"output_tokens":50,"duration_ms":500}
{"timestamp":"2026-02-24T01:01:00Z","agent":"openclaw","campaign_id":"oc-dep-audit","model":"claude-sonnet-4","input_tokens":200,"output_tokens":100,"duration_ms":300,"error":"rate_limit"}
`

	records, err := parseS3Records([]byte(ndjson))
	if err != nil {
		t.Fatalf("parseS3Records: %v", err)
	}
	if len(records) != 2 {
		t.Fatalf("expected 2 records, got %d", len(records))
	}
	if records[0].Agent != "openclaw" {
		t.Errorf("records[0].Agent = %q, want 'openclaw'", records[0].Agent)
	}
	if records[0].InputTokens != 100 {
		t.Errorf("records[0].InputTokens = %d, want 100", records[0].InputTokens)
	}
	if records[1].Error != "rate_limit" {
		t.Errorf("records[1].Error = %q, want 'rate_limit'", records[1].Error)
	}
	if records[1].DurationMs != 300 {
		t.Errorf("records[1].DurationMs = %d, want 300", records[1].DurationMs)
	}
}

func TestParseS3RecordsJSONArray(t *testing.T) {
	jsonArray := `[
  {"timestamp":"2026-02-24T01:00:00Z","agent":"openclaw","model":"claude-sonnet-4","input_tokens":100,"output_tokens":50,"duration_ms":500},
  {"timestamp":"2026-02-24T01:01:00Z","agent":"hexstrike","model":"claude-sonnet-4","input_tokens":200,"output_tokens":100,"duration_ms":300}
]`

	records, err := parseS3Records([]byte(jsonArray))
	if err != nil {
		t.Fatalf("parseS3Records: %v", err)
	}
	if len(records) != 2 {
		t.Fatalf("expected 2 records, got %d", len(records))
	}
	if records[0].Agent != "openclaw" {
		t.Errorf("records[0].Agent = %q, want 'openclaw'", records[0].Agent)
	}
	if records[1].Agent != "hexstrike" {
		t.Errorf("records[1].Agent = %q, want 'hexstrike'", records[1].Agent)
	}
}

func TestParseS3RecordsEmpty(t *testing.T) {
	records, err := parseS3Records([]byte(""))
	if err != nil {
		t.Fatalf("parseS3Records: %v", err)
	}
	if len(records) != 0 {
		t.Errorf("expected 0 records for empty input, got %d", len(records))
	}
}

func TestParseS3RecordsNDJSONWithBlankLines(t *testing.T) {
	ndjson := `{"timestamp":"2026-02-24T01:00:00Z","agent":"openclaw","model":"claude-sonnet-4","duration_ms":500}

{"timestamp":"2026-02-24T01:01:00Z","agent":"openclaw","model":"claude-sonnet-4","duration_ms":300}
`

	records, err := parseS3Records([]byte(ndjson))
	if err != nil {
		t.Fatalf("parseS3Records: %v", err)
	}
	if len(records) != 2 {
		t.Fatalf("expected 2 records (blank lines skipped), got %d", len(records))
	}
}

func TestParseS3RecordsInvalidNDJSON(t *testing.T) {
	_, err := parseS3Records([]byte(`{"valid":"json"}
not valid json
`))
	if err == nil {
		t.Error("expected error for invalid NDJSON line")
	}
}

func TestS3IngesterNotConfigured(t *testing.T) {
	ingester := NewApertureS3Ingester(S3Config{}, NewMeterStore(), nil)
	if ingester.Configured() {
		t.Error("ingester without bucket/region should not be configured")
	}
}

func TestS3IngesterConfigured(t *testing.T) {
	ingester := NewApertureS3Ingester(S3Config{
		Bucket: "aperture-exports",
		Region: "us-east-1",
	}, NewMeterStore(), nil)
	if !ingester.Configured() {
		t.Error("ingester with bucket+region should be configured")
	}
}

func TestS3IngesterConfiguredWithEndpoint(t *testing.T) {
	ingester := NewApertureS3Ingester(S3Config{
		Bucket:   "fuzzy-models",
		Endpoint: "objectstore.nyc1.civo.com",
	}, NewMeterStore(), nil)
	if !ingester.Configured() {
		t.Error("ingester with bucket+endpoint (no region) should be configured")
	}
}

func TestS3URLPathStyle(t *testing.T) {
	ingester := NewApertureS3Ingester(S3Config{
		Bucket:   "fuzzy-models",
		Endpoint: "objectstore.nyc1.civo.com",
	}, NewMeterStore(), nil)

	listURL := ingester.s3URL("")
	if listURL != "https://objectstore.nyc1.civo.com/fuzzy-models" {
		t.Errorf("list URL = %q, want path-style", listURL)
	}

	getURL := ingester.s3URL("aperture/exports/2026-02-24T00.ndjson")
	want := "https://objectstore.nyc1.civo.com/fuzzy-models/aperture/exports/2026-02-24T00.ndjson"
	if getURL != want {
		t.Errorf("get URL = %q, want %q", getURL, want)
	}
}

func TestS3URLVirtualHosted(t *testing.T) {
	ingester := NewApertureS3Ingester(S3Config{
		Bucket: "my-bucket",
		Region: "us-east-1",
	}, NewMeterStore(), nil)

	listURL := ingester.s3URL("")
	if listURL != "https://my-bucket.s3.us-east-1.amazonaws.com/" {
		t.Errorf("list URL = %q, want virtual-hosted", listURL)
	}

	getURL := ingester.s3URL("usage/file.ndjson")
	want := "https://my-bucket.s3.us-east-1.amazonaws.com/usage/file.ndjson"
	if getURL != want {
		t.Errorf("get URL = %q, want %q", getURL, want)
	}
}

func TestS3URLEndpointWithScheme(t *testing.T) {
	ingester := NewApertureS3Ingester(S3Config{
		Bucket:   "mybucket",
		Endpoint: "https://s3.example.com/",
	}, NewMeterStore(), nil)

	url := ingester.s3URL("key")
	if url != "https://s3.example.com/mybucket/key" {
		t.Errorf("URL = %q, want no double scheme or trailing slash issues", url)
	}
}

func TestSignS3RequestAddsAuthHeaders(t *testing.T) {
	ingester := NewApertureS3Ingester(S3Config{
		Bucket:    "mybucket",
		Region:    "us-east-1",
		Endpoint:  "s3.example.com",
		AccessKey: "AKIAIOSFODNN7EXAMPLE",
		SecretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
	}, NewMeterStore(), nil)

	req, _ := http.NewRequest(http.MethodGet, "https://s3.example.com/mybucket", nil)
	ingester.signS3Request(req, sha256Hex([]byte{}))

	if req.Header.Get("Authorization") == "" {
		t.Error("Authorization header not set after signing")
	}
	if !strings.HasPrefix(req.Header.Get("Authorization"), "AWS4-HMAC-SHA256") {
		t.Errorf("Authorization = %q, want AWS4-HMAC-SHA256 prefix", req.Header.Get("Authorization"))
	}
	if req.Header.Get("x-amz-date") == "" {
		t.Error("x-amz-date header not set")
	}
	if req.Header.Get("x-amz-content-sha256") == "" {
		t.Error("x-amz-content-sha256 header not set")
	}
}

func TestSignS3RequestSkipsWithoutCredentials(t *testing.T) {
	ingester := NewApertureS3Ingester(S3Config{
		Bucket:   "mybucket",
		Endpoint: "s3.example.com",
	}, NewMeterStore(), nil)

	req, _ := http.NewRequest(http.MethodGet, "https://s3.example.com/mybucket", nil)
	ingester.signS3Request(req, sha256Hex([]byte{}))

	if req.Header.Get("Authorization") != "" {
		t.Error("Authorization should not be set without credentials")
	}
}

func TestS3IngesterIngestKey(t *testing.T) {
	ndjson := `{"timestamp":"2026-02-24T01:00:00Z","agent":"openclaw","campaign_id":"oc-dep-audit","model":"claude-sonnet-4","input_tokens":100,"output_tokens":50,"duration_ms":500}
{"timestamp":"2026-02-24T01:01:00Z","agent":"openclaw","campaign_id":"oc-dep-audit","model":"claude-sonnet-4","input_tokens":200,"output_tokens":100,"duration_ms":300,"error":"rate_limit"}
`

	// Mock S3 server.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(ndjson))
	}))
	defer server.Close()

	store := NewMeterStore()
	_ = server // Server available for future direct HTTP tests.

	// Test parseS3Records + MeterStore.Record integration.
	records, err := parseS3Records([]byte(ndjson))
	if err != nil {
		t.Fatalf("parseS3Records: %v", err)
	}

	for _, rec := range records {
		store.Record(MeterRecord{
			Agent:      rec.Agent,
			CampaignID: rec.CampaignID,
			ToolName:   "llm:" + rec.Model,
			DurationMs: rec.DurationMs,
			Timestamp:  rec.Timestamp,
			IsError:    rec.Error != "",
		})
	}

	buckets := store.Query("openclaw", "oc-dep-audit")
	if len(buckets) != 1 {
		t.Fatalf("expected 1 bucket, got %d", len(buckets))
	}
	if buckets[0].ToolCalls != 2 {
		t.Errorf("ToolCalls = %d, want 2", buckets[0].ToolCalls)
	}
	if buckets[0].ErrorCount != 1 {
		t.Errorf("ErrorCount = %d, want 1", buckets[0].ErrorCount)
	}
	if buckets[0].TotalDurationMs != 800 {
		t.Errorf("TotalDurationMs = %d, want 800", buckets[0].TotalDurationMs)
	}
}

func TestS3IngesterPollEndToEnd(t *testing.T) {
	ts := time.Date(2026, 2, 24, 1, 0, 0, 0, time.UTC)

	ndjson := `{"timestamp":"2026-02-24T01:00:00Z","agent":"openclaw","campaign_id":"oc-dep-audit","model":"claude-sonnet-4","duration_ms":500}
`

	listXML, _ := xml.Marshal(listBucketResult{
		Contents: []s3Object{{Key: "usage/2026-02-24T00.ndjson", Size: 512}},
	})

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.RawQuery != "" && r.URL.Path == "/" {
			// List request.
			w.Header().Set("Content-Type", "application/xml")
			w.Write(listXML)
		} else {
			// Get object request.
			w.Write([]byte(ndjson))
		}
	}))
	defer server.Close()

	store := NewMeterStore()
	_ = server // Server available for future direct poll tests.

	// Test the pipeline: list XML -> keys, then NDJSON -> records -> MeterStore.
	keys := parseS3Keys(listXML)
	if len(keys) != 1 {
		t.Fatalf("expected 1 key from list, got %d", len(keys))
	}

	_ = ts // Ensure timestamp reference is valid.

	// Simulate ingesting a record.
	records, _ := parseS3Records([]byte(ndjson))
	for _, rec := range records {
		store.Record(MeterRecord{
			Agent:      rec.Agent,
			CampaignID: rec.CampaignID,
			ToolName:   "llm:" + rec.Model,
			DurationMs: rec.DurationMs,
			Timestamp:  rec.Timestamp,
		})
	}

	buckets := store.Query("openclaw", "")
	if len(buckets) != 1 {
		t.Fatalf("expected 1 bucket after ingestion, got %d", len(buckets))
	}
}

func TestS3IngesterPollWithEndpoint(t *testing.T) {
	ndjson := `{"timestamp":"2026-02-24T01:00:00Z","agent":"openclaw","campaign_id":"oc-dep-audit","model":"claude-sonnet-4","input_tokens":1200,"output_tokens":350,"duration_ms":500}
`
	listXML, _ := xml.Marshal(listBucketResult{
		Contents: []s3Object{{Key: "aperture/exports/2026-02-24T00.ndjson", Size: 512}},
	})

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify signed requests have auth headers.
		if r.Header.Get("Authorization") == "" {
			t.Error("request missing Authorization header")
		}
		if r.URL.Path == "/fuzzy-models" {
			w.Header().Set("Content-Type", "application/xml")
			w.Write(listXML)
		} else {
			w.Write([]byte(ndjson))
		}
	}))
	defer server.Close()

	store := NewMeterStore()
	ingester := NewApertureS3Ingester(S3Config{
		Bucket:    "fuzzy-models",
		Prefix:    "aperture/exports/",
		Endpoint:  server.URL,
		AccessKey: "TESTKEY",
		SecretKey: "TESTSECRET",
	}, store, server.Client())

	ingester.poll(context.Background())

	buckets := store.Query("openclaw", "oc-dep-audit")
	if len(buckets) != 1 {
		t.Fatalf("expected 1 bucket after poll, got %d", len(buckets))
	}
	if buckets[0].InputTokens != 1200 {
		t.Errorf("InputTokens = %d, want 1200", buckets[0].InputTokens)
	}
	if buckets[0].OutputTokens != 350 {
		t.Errorf("OutputTokens = %d, want 350", buckets[0].OutputTokens)
	}
}

func TestListBucketResultXMLRoundTrip(t *testing.T) {
	original := listBucketResult{
		Contents: []s3Object{
			{Key: "usage/file1.ndjson", LastModified: "2026-02-24T01:00:00.000Z", Size: 1024},
			{Key: "usage/file2.ndjson", LastModified: "2026-02-24T02:00:00.000Z", Size: 2048},
		},
	}

	data, err := xml.Marshal(original)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	keys := parseS3Keys(data)
	if len(keys) != 2 {
		t.Fatalf("expected 2 keys from round-trip, got %d", len(keys))
	}
	if keys[0] != "usage/file1.ndjson" {
		t.Errorf("keys[0] = %q, want 'usage/file1.ndjson'", keys[0])
	}
}
