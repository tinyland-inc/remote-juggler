// RemoteJuggler Linux Tray Tests
//
// Unit tests for configuration loading, identity management, and state handling.
//
// Run with: go test -v ./...

package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// =============================================================================
// Configuration Tests
// =============================================================================

func TestLoadConfigFromJSON(t *testing.T) {
	configJSON := `{
		"identities": {
			"personal": {
				"provider": "gitlab",
				"host": "gitlab-personal",
				"hostname": "gitlab.com",
				"user": "personaluser",
				"email": "personal@example.com"
			},
			"work": {
				"provider": "github",
				"host": "github.com",
				"hostname": "github.com",
				"user": "workuser",
				"email": "work@company.com",
				"gpg": {
					"keyId": "ABCD1234",
					"signCommits": true,
					"securityMode": "trusted_workstation"
				}
			}
		},
		"settings": {
			"defaultProvider": "gitlab",
			"autoDetect": true
		}
	}`

	var config Config
	err := json.Unmarshal([]byte(configJSON), &config)
	if err != nil {
		t.Fatalf("Failed to parse config: %v", err)
	}

	if len(config.Identities) != 2 {
		t.Errorf("Expected 2 identities, got %d", len(config.Identities))
	}

	personal, ok := config.Identities["personal"]
	if !ok {
		t.Fatal("Missing personal identity")
	}
	if personal.Provider != "gitlab" {
		t.Errorf("Expected provider 'gitlab', got '%s'", personal.Provider)
	}
	if personal.Email != "personal@example.com" {
		t.Errorf("Expected email 'personal@example.com', got '%s'", personal.Email)
	}

	work, ok := config.Identities["work"]
	if !ok {
		t.Fatal("Missing work identity")
	}
	if work.Gpg == nil {
		t.Fatal("Missing GPG config for work identity")
	}
	if work.Gpg.KeyId != "ABCD1234" {
		t.Errorf("Expected GPG keyId 'ABCD1234', got '%s'", work.Gpg.KeyId)
	}
	if !work.Gpg.SignCommits {
		t.Error("Expected signCommits to be true")
	}
	if work.Gpg.SecurityMode != SecurityModeTrusted {
		t.Errorf("Expected securityMode 'trusted_workstation', got '%s'", work.Gpg.SecurityMode)
	}
}

func TestLoadConfigMinimal(t *testing.T) {
	configJSON := `{
		"identities": {}
	}`

	var config Config
	err := json.Unmarshal([]byte(configJSON), &config)
	if err != nil {
		t.Fatalf("Failed to parse minimal config: %v", err)
	}

	if len(config.Identities) != 0 {
		t.Errorf("Expected 0 identities, got %d", len(config.Identities))
	}
}

func TestLoadConfigFromFile(t *testing.T) {
	// Create temp directory
	tempDir, err := os.MkdirTemp("", "remotejuggler-test")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	// Write test config
	configPath := filepath.Join(tempDir, "config.json")
	configJSON := `{
		"identities": {
			"test": {
				"provider": "github",
				"host": "github.com",
				"user": "testuser",
				"email": "test@example.com"
			}
		}
	}`
	err = os.WriteFile(configPath, []byte(configJSON), 0600)
	if err != nil {
		t.Fatalf("Failed to write config: %v", err)
	}

	// Read and parse
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("Failed to read config: %v", err)
	}

	var config Config
	err = json.Unmarshal(data, &config)
	if err != nil {
		t.Fatalf("Failed to parse config: %v", err)
	}

	if _, ok := config.Identities["test"]; !ok {
		t.Error("Missing test identity")
	}
}

// =============================================================================
// Security Mode Tests
// =============================================================================

func TestSecurityModeConstants(t *testing.T) {
	tests := []struct {
		mode     SecurityMode
		expected string
	}{
		{SecurityModeMaximum, "maximum_security"},
		{SecurityModeDeveloper, "developer_workflow"},
		{SecurityModeTrusted, "trusted_workstation"},
	}

	for _, tt := range tests {
		if string(tt.mode) != tt.expected {
			t.Errorf("Expected %s, got %s", tt.expected, tt.mode)
		}
	}
}

func TestSecurityModeSerialization(t *testing.T) {
	gpg := GpgConfig{
		KeyId:        "TEST123",
		SignCommits:  true,
		SecurityMode: SecurityModeTrusted,
	}

	data, err := json.Marshal(gpg)
	if err != nil {
		t.Fatalf("Failed to marshal: %v", err)
	}

	var parsed GpgConfig
	err = json.Unmarshal(data, &parsed)
	if err != nil {
		t.Fatalf("Failed to unmarshal: %v", err)
	}

	if parsed.SecurityMode != SecurityModeTrusted {
		t.Errorf("Expected trusted_workstation, got %s", parsed.SecurityMode)
	}
}

// =============================================================================
// Global State Tests
// =============================================================================

func TestGlobalStateDefaults(t *testing.T) {
	stateJSON := `{
		"version": "2.0.0",
		"currentIdentity": "personal"
	}`

	var state GlobalState
	err := json.Unmarshal([]byte(stateJSON), &state)
	if err != nil {
		t.Fatalf("Failed to parse state: %v", err)
	}

	if state.Version != "2.0.0" {
		t.Errorf("Expected version '2.0.0', got '%s'", state.Version)
	}
	if state.CurrentIdentity != "personal" {
		t.Errorf("Expected currentIdentity 'personal', got '%s'", state.CurrentIdentity)
	}
}

func TestGlobalStateWithTray(t *testing.T) {
	stateJSON := `{
		"version": "2.0.0",
		"currentIdentity": "work",
		"forceMode": true,
		"tray": {
			"showNotifications": true,
			"autoStartEnabled": false,
			"iconStyle": "monochrome"
		},
		"recentIdentities": ["work", "personal"]
	}`

	var state GlobalState
	err := json.Unmarshal([]byte(stateJSON), &state)
	if err != nil {
		t.Fatalf("Failed to parse state: %v", err)
	}

	if !state.ForceMode {
		t.Error("Expected forceMode to be true")
	}
	if !state.Tray.ShowNotifications {
		t.Error("Expected showNotifications to be true")
	}
	if state.Tray.AutoStartEnabled {
		t.Error("Expected autoStartEnabled to be false")
	}
	if state.Tray.IconStyle != "monochrome" {
		t.Errorf("Expected iconStyle 'monochrome', got '%s'", state.Tray.IconStyle)
	}
	if len(state.RecentIdentities) != 2 {
		t.Errorf("Expected 2 recent identities, got %d", len(state.RecentIdentities))
	}
}

func TestGlobalStateWithLastSwitch(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	state := GlobalState{
		Version:         "2.0.0",
		CurrentIdentity: "test",
		LastSwitch:      &now,
	}

	data, err := json.Marshal(state)
	if err != nil {
		t.Fatalf("Failed to marshal: %v", err)
	}

	var parsed GlobalState
	err = json.Unmarshal(data, &parsed)
	if err != nil {
		t.Fatalf("Failed to unmarshal: %v", err)
	}

	if parsed.LastSwitch == nil {
		t.Fatal("Expected LastSwitch to be set")
	}
	if !parsed.LastSwitch.Equal(now) {
		t.Errorf("LastSwitch mismatch: expected %v, got %v", now, *parsed.LastSwitch)
	}
}

// =============================================================================
// Identity Conversion Tests
// =============================================================================

func TestIdentityFromConfig(t *testing.T) {
	identConfig := IdentityConfig{
		Provider: "gitlab",
		Host:     "gitlab-work",
		Hostname: "gitlab.com",
		User:     "workuser",
		Email:    "work@company.com",
		Gpg: &GpgConfig{
			KeyId:       "GPG123",
			SignCommits: true,
		},
	}

	// Simulate conversion (the actual loadConfig does this)
	identity := Identity{
		Name:     "work",
		Provider: identConfig.Provider,
		Email:    identConfig.Email,
		Host:     identConfig.Host,
		Gpg:      identConfig.Gpg,
	}

	if identity.Name != "work" {
		t.Errorf("Expected name 'work', got '%s'", identity.Name)
	}
	if identity.Provider != "gitlab" {
		t.Errorf("Expected provider 'gitlab', got '%s'", identity.Provider)
	}
	if identity.Gpg == nil {
		t.Fatal("Expected GPG config")
	}
	if identity.Gpg.KeyId != "GPG123" {
		t.Errorf("Expected keyId 'GPG123', got '%s'", identity.Gpg.KeyId)
	}
}

// =============================================================================
// Settings Tests
// =============================================================================

func TestConfigSettings(t *testing.T) {
	configJSON := `{
		"identities": {},
		"settings": {
			"defaultProvider": "github",
			"autoDetect": true,
			"useKeychain": true,
			"gpgSign": true,
			"defaultSecurityMode": "maximum_security",
			"hsmAvailable": true,
			"trustedWorkstationRequiresHSM": true
		}
	}`

	var config Config
	err := json.Unmarshal([]byte(configJSON), &config)
	if err != nil {
		t.Fatalf("Failed to parse config: %v", err)
	}

	if config.Settings == nil {
		t.Fatal("Expected settings to be set")
	}
	if config.Settings.DefaultProvider != "github" {
		t.Errorf("Expected defaultProvider 'github', got '%s'", config.Settings.DefaultProvider)
	}
	if !config.Settings.AutoDetect {
		t.Error("Expected autoDetect to be true")
	}
	if !config.Settings.UseKeychain {
		t.Error("Expected useKeychain to be true")
	}
	if !config.Settings.GpgSign {
		t.Error("Expected gpgSign to be true")
	}
	if config.Settings.DefaultSecurityMode != SecurityModeMaximum {
		t.Errorf("Expected securityMode 'maximum_security', got '%s'", config.Settings.DefaultSecurityMode)
	}
	if !config.Settings.HsmAvailable {
		t.Error("Expected hsmAvailable to be true")
	}
}

// =============================================================================
// Path Tests
// =============================================================================

func TestGetConfigDir(t *testing.T) {
	// Save and restore HOME
	origHome := os.Getenv("HOME")
	defer os.Setenv("HOME", origHome)

	// Set a test HOME
	tempDir, err := os.MkdirTemp("", "remotejuggler-home")
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	os.Setenv("HOME", tempDir)

	dir := getConfigDir()

	expected := filepath.Join(tempDir, ".config", "remote-juggler")
	if dir != expected {
		t.Errorf("Expected config dir '%s', got '%s'", expected, dir)
	}
}

// =============================================================================
// Benchmark Tests
// =============================================================================

func BenchmarkConfigParsing(b *testing.B) {
	configJSON := `{
		"identities": {
			"id1": {"provider": "gitlab", "host": "h1", "user": "u1", "email": "e1@test.com"},
			"id2": {"provider": "github", "host": "h2", "user": "u2", "email": "e2@test.com"},
			"id3": {"provider": "bitbucket", "host": "h3", "user": "u3", "email": "e3@test.com"}
		},
		"settings": {
			"defaultProvider": "gitlab",
			"autoDetect": true
		}
	}`

	for i := 0; i < b.N; i++ {
		var config Config
		_ = json.Unmarshal([]byte(configJSON), &config)
	}
}

func BenchmarkStateParsing(b *testing.B) {
	stateJSON := `{
		"version": "2.0.0",
		"currentIdentity": "personal",
		"forceMode": false,
		"tray": {
			"showNotifications": true,
			"autoStartEnabled": true,
			"iconStyle": "color"
		},
		"recentIdentities": ["personal", "work", "github"]
	}`

	for i := 0; i < b.N; i++ {
		var state GlobalState
		_ = json.Unmarshal([]byte(stateJSON), &state)
	}
}
