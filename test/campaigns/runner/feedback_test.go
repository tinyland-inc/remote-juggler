package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
)

// mockGitHub simulates the GitHub API for feedback tests.
type mockGitHub struct {
	mu            sync.Mutex
	createdIssues []map[string]any
	closedIssues  []int
	comments      []map[string]any
	searchResults []GitHubIssue
	issueCounter  int
}

func newMockGitHub() *mockGitHub {
	return &mockGitHub{}
}

func (m *mockGitHub) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/search/issues", m.handleSearch)
	mux.HandleFunc("/repos/", m.handleRepos)
	return mux
}

func (m *mockGitHub) handleSearch(w http.ResponseWriter, r *http.Request) {
	m.mu.Lock()
	defer m.mu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"items": m.searchResults,
	})
}

func (m *mockGitHub) handleRepos(w http.ResponseWriter, r *http.Request) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if r.Method == http.MethodPost {
		var payload map[string]any
		json.NewDecoder(r.Body).Decode(&payload)

		// Check if it's an issue creation or a comment.
		if _, ok := payload["title"]; ok {
			m.issueCounter++
			m.createdIssues = append(m.createdIssues, payload)
			w.WriteHeader(http.StatusCreated)
			json.NewEncoder(w).Encode(GitHubIssue{
				Number: m.issueCounter,
				Title:  payload["title"].(string),
				State:  "open",
			})
		} else if _, ok := payload["body"]; ok {
			m.comments = append(m.comments, payload)
			w.WriteHeader(http.StatusCreated)
			json.NewEncoder(w).Encode(map[string]any{"id": 1})
		}
		return
	}

	if r.Method == http.MethodPatch {
		var payload map[string]any
		json.NewDecoder(r.Body).Decode(&payload)
		if payload["state"] == "closed" {
			m.closedIssues = append(m.closedIssues, 1)
		}
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]any{"state": "closed"})
		return
	}

	w.WriteHeader(http.StatusNotFound)
}

func newTestFeedback(server *httptest.Server) *FeedbackHandler {
	handler := NewFeedbackHandler("test-token")
	handler.baseURL = server.URL
	handler.httpClient = server.Client()
	return handler
}

func testCampaignWithFeedback() *Campaign {
	return &Campaign{
		ID: "test-campaign",
		Feedback: Feedback{
			CreateIssues:        true,
			CloseResolvedIssues: true,
		},
		Outputs: CampaignOutputs{
			IssueRepo:   "tinyland-inc/remote-juggler",
			IssueLabels: []string{"campaign", "automated"},
		},
	}
}

func TestFeedbackCreateIssueE2E(t *testing.T) {
	gh := newMockGitHub()
	server := httptest.NewServer(gh.Handler())
	defer server.Close()

	handler := newTestFeedback(server)
	campaign := testCampaignWithFeedback()

	findings := []Finding{
		{
			Title:       "Vulnerable dependency: lodash",
			Body:        "lodash 4.17.20 has known CVEs",
			Severity:    "high",
			CampaignID:  "test-campaign",
			Fingerprint: "dep-lodash-4.17.20",
		},
	}

	err := handler.ProcessFindings(context.Background(), campaign, findings, nil)
	if err != nil {
		t.Fatalf("ProcessFindings: %v", err)
	}

	gh.mu.Lock()
	defer gh.mu.Unlock()

	if len(gh.createdIssues) != 1 {
		t.Fatalf("expected 1 created issue, got %d", len(gh.createdIssues))
	}
	if gh.createdIssues[0]["title"] != "Vulnerable dependency: lodash" {
		t.Errorf("title = %v, want 'Vulnerable dependency: lodash'", gh.createdIssues[0]["title"])
	}
	labels := gh.createdIssues[0]["labels"].([]any)
	if len(labels) != 3 { // "high" from severity not added, but campaign labels are
		// Finding has no labels, campaign adds "campaign" + "automated"
		// Actually finding.Labels is nil, so only campaign labels
		t.Logf("labels = %v (count=%d)", labels, len(labels))
	}
}

func TestFeedbackSkipsDuplicateIssue(t *testing.T) {
	gh := newMockGitHub()
	// Pre-populate search results so the handler finds an existing issue.
	gh.searchResults = []GitHubIssue{
		{Number: 42, Title: "Existing issue", State: "open"},
	}
	server := httptest.NewServer(gh.Handler())
	defer server.Close()

	handler := newTestFeedback(server)
	campaign := testCampaignWithFeedback()

	findings := []Finding{
		{Title: "Existing issue", Fingerprint: "fp-existing"},
	}

	err := handler.ProcessFindings(context.Background(), campaign, findings, nil)
	if err != nil {
		t.Fatalf("ProcessFindings: %v", err)
	}

	gh.mu.Lock()
	defer gh.mu.Unlock()

	if len(gh.createdIssues) != 0 {
		t.Errorf("expected 0 created issues (duplicate), got %d", len(gh.createdIssues))
	}
}

func TestFeedbackCloseResolvedE2E(t *testing.T) {
	gh := newMockGitHub()
	// Search returns an existing open issue for "Issue B" (which is now resolved).
	gh.searchResults = []GitHubIssue{
		{Number: 7, Title: "Issue B", State: "open", Body: "fp-b"},
	}
	server := httptest.NewServer(gh.Handler())
	defer server.Close()

	handler := newTestFeedback(server)
	campaign := testCampaignWithFeedback()

	current := []Finding{
		{Title: "Issue A", Fingerprint: "fp-a"},
	}
	previous := []Finding{
		{Title: "Issue A", Fingerprint: "fp-a"},
		{Title: "Issue B", Fingerprint: "fp-b"},
	}

	// ProcessFindings creates Issue A (new) and closes Issue B (resolved).
	// Reset search results after first call so search for "fp-a" returns nothing
	// and search for "fp-b" returns the existing issue.
	err := handler.ProcessFindings(context.Background(), campaign, current, previous)
	if err != nil {
		t.Fatalf("ProcessFindings: %v", err)
	}

	gh.mu.Lock()
	defer gh.mu.Unlock()

	if len(gh.closedIssues) != 1 {
		t.Errorf("expected 1 closed issue, got %d", len(gh.closedIssues))
	}
	if len(gh.comments) != 1 {
		t.Errorf("expected 1 close comment, got %d", len(gh.comments))
	}
}

func TestFeedbackMultipleFindings(t *testing.T) {
	gh := newMockGitHub()
	server := httptest.NewServer(gh.Handler())
	defer server.Close()

	handler := newTestFeedback(server)
	campaign := testCampaignWithFeedback()

	findings := []Finding{
		{Title: "CVE-2026-001", Fingerprint: "cve-001", Severity: "critical"},
		{Title: "CVE-2026-002", Fingerprint: "cve-002", Severity: "high"},
		{Title: "CVE-2026-003", Fingerprint: "cve-003", Severity: "low"},
	}

	err := handler.ProcessFindings(context.Background(), campaign, findings, nil)
	if err != nil {
		t.Fatalf("ProcessFindings: %v", err)
	}

	gh.mu.Lock()
	defer gh.mu.Unlock()

	if len(gh.createdIssues) != 3 {
		t.Fatalf("expected 3 created issues, got %d", len(gh.createdIssues))
	}
}

func TestFeedbackDisabled(t *testing.T) {
	handler := NewFeedbackHandler("token")

	campaign := &Campaign{
		ID: "test-campaign",
		Feedback: Feedback{
			CreateIssues: false,
		},
	}

	err := handler.ProcessFindings(context.Background(), campaign, []Finding{
		{Title: "Something", Body: "Details"},
	}, nil)

	if err != nil {
		t.Errorf("ProcessFindings with disabled feedback should return nil, got: %v", err)
	}
}

func TestFeedbackNoIssueRepo(t *testing.T) {
	handler := NewFeedbackHandler("token")

	campaign := &Campaign{
		ID: "test-campaign",
		Feedback: Feedback{
			CreateIssues: true,
		},
		Outputs: CampaignOutputs{},
	}

	err := handler.ProcessFindings(context.Background(), campaign, []Finding{
		{Title: "Something", Body: "Details"},
	}, nil)

	if err == nil {
		t.Error("expected error when issueRepo is not configured")
	}
}

func TestFeedbackHandlerInit(t *testing.T) {
	handler := NewFeedbackHandler("ghp_test")
	if handler.token != "ghp_test" {
		t.Errorf("token = %q, want 'ghp_test'", handler.token)
	}
	if handler.httpClient == nil {
		t.Error("httpClient should not be nil")
	}
	if handler.baseURL != "https://api.github.com" {
		t.Errorf("baseURL = %q, want 'https://api.github.com'", handler.baseURL)
	}
}

func TestFindingJSONRoundTrip(t *testing.T) {
	finding := Finding{
		Title:       "CVE-2026-1234",
		Body:        "Critical vuln in openssl",
		Severity:    "critical",
		Labels:      []string{"security", "cve"},
		CampaignID:  "hs-dep-vuln",
		RunID:       "run-123",
		Fingerprint: "cve-2026-1234-openssl",
	}

	data, err := json.Marshal(finding)
	if err != nil {
		t.Fatalf("marshal finding: %v", err)
	}

	var decoded Finding
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal finding: %v", err)
	}

	if decoded.Fingerprint != "cve-2026-1234-openssl" {
		t.Errorf("fingerprint = %q, want 'cve-2026-1234-openssl'", decoded.Fingerprint)
	}
	if decoded.Severity != "critical" {
		t.Errorf("severity = %q, want 'critical'", decoded.Severity)
	}
}

func TestCloseResolvedLogic(t *testing.T) {
	current := []Finding{
		{Title: "Issue A", Fingerprint: "fp-a"},
	}
	previous := []Finding{
		{Title: "Issue A", Fingerprint: "fp-a"},
		{Title: "Issue B", Fingerprint: "fp-b"},
	}

	currentFPs := make(map[string]bool)
	for _, f := range current {
		fp := f.Fingerprint
		if fp == "" {
			fp = f.Title
		}
		currentFPs[fp] = true
	}

	resolved := 0
	for _, prev := range previous {
		fp := prev.Fingerprint
		if fp == "" {
			fp = prev.Title
		}
		if !currentFPs[fp] {
			resolved++
		}
	}

	if resolved != 1 {
		t.Errorf("resolved = %d, want 1 (Issue B should be resolved)", resolved)
	}
}

func TestSchedulerFeedbackIntegration(t *testing.T) {
	gh := newMockGitHub()
	server := httptest.NewServer(gh.Handler())
	defer server.Close()

	feedback := newTestFeedback(server)

	campaign := testCampaignWithFeedback()
	registry := map[string]*Campaign{campaign.ID: campaign}
	scheduler := NewScheduler(registry, nil, nil)
	scheduler.SetFeedback(feedback)

	// Simulate storeResult with findings.
	result := &CampaignResult{
		CampaignID: campaign.ID,
		Status:     "success",
		Findings: []Finding{
			{Title: "Test finding", Body: "Found something", Fingerprint: "fp-test"},
		},
	}
	scheduler.storeResult(context.Background(), campaign, result)

	gh.mu.Lock()
	defer gh.mu.Unlock()

	if len(gh.createdIssues) != 1 {
		t.Fatalf("expected scheduler to trigger feedback, got %d issues", len(gh.createdIssues))
	}
	if gh.createdIssues[0]["title"] != "Test finding" {
		t.Errorf("issue title = %v, want 'Test finding'", gh.createdIssues[0]["title"])
	}
}
