package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultConfig(t *testing.T) {
	cfg := DefaultConfig()

	if cfg.Listen != ":443" {
		t.Errorf("Listen = %q, want %q", cfg.Listen, ":443")
	}
	if cfg.ChapelBinary != "remote-juggler" {
		t.Errorf("ChapelBinary = %q, want %q", cfg.ChapelBinary, "remote-juggler")
	}
	if cfg.SetecPrefix != "remotejuggler/" {
		t.Errorf("SetecPrefix = %q, want %q", cfg.SetecPrefix, "remotejuggler/")
	}
	if len(cfg.Precedence) != 4 {
		t.Fatalf("Precedence length = %d, want 4", len(cfg.Precedence))
	}
	expected := []string{"env", "sops", "kdbx", "setec"}
	for i, v := range expected {
		if cfg.Precedence[i] != v {
			t.Errorf("Precedence[%d] = %q, want %q", i, cfg.Precedence[i], v)
		}
	}
	if cfg.Tailscale.Hostname != "rj-gateway" {
		t.Errorf("Tailscale.Hostname = %q, want %q", cfg.Tailscale.Hostname, "rj-gateway")
	}
}

func TestLoadConfigFromFile(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")

	data := []byte(`{
		"listen": ":8080",
		"chapel_binary": "/usr/local/bin/rj",
		"setec_url": "https://setec.example.ts.net",
		"setec_prefix": "myapp/",
		"setec_secrets": ["token-a", "token-b"],
		"precedence": ["setec", "env"],
		"tailscale": {
			"hostname": "custom-gw",
			"state_dir": "/tmp/ts"
		}
	}`)
	if err := os.WriteFile(cfgPath, data, 0644); err != nil {
		t.Fatal(err)
	}

	cfg, err := LoadConfig(cfgPath)
	if err != nil {
		t.Fatal(err)
	}

	if cfg.Listen != ":8080" {
		t.Errorf("Listen = %q, want %q", cfg.Listen, ":8080")
	}
	if cfg.ChapelBinary != "/usr/local/bin/rj" {
		t.Errorf("ChapelBinary = %q, want %q", cfg.ChapelBinary, "/usr/local/bin/rj")
	}
	if cfg.SetecURL != "https://setec.example.ts.net" {
		t.Errorf("SetecURL = %q", cfg.SetecURL)
	}
	if cfg.SetecPrefix != "myapp/" {
		t.Errorf("SetecPrefix = %q, want %q", cfg.SetecPrefix, "myapp/")
	}
	if len(cfg.SetecSecrets) != 2 {
		t.Fatalf("SetecSecrets length = %d, want 2", len(cfg.SetecSecrets))
	}
	if len(cfg.Precedence) != 2 || cfg.Precedence[0] != "setec" {
		t.Errorf("Precedence = %v, want [setec env]", cfg.Precedence)
	}
	if cfg.Tailscale.Hostname != "custom-gw" {
		t.Errorf("Tailscale.Hostname = %q", cfg.Tailscale.Hostname)
	}
	if cfg.Tailscale.StateDir != "/tmp/ts" {
		t.Errorf("Tailscale.StateDir = %q", cfg.Tailscale.StateDir)
	}
}

func TestLoadConfigEmptyPath(t *testing.T) {
	cfg, err := LoadConfig("")
	if err != nil {
		t.Fatal(err)
	}
	// Should return defaults.
	if cfg.Listen != ":443" {
		t.Errorf("Listen = %q, want default %q", cfg.Listen, ":443")
	}
}

func TestLoadConfigMissingFile(t *testing.T) {
	_, err := LoadConfig("/nonexistent/path/config.json")
	if err == nil {
		t.Error("expected error for missing file, got nil")
	}
}

func TestLoadConfigInvalidJSON(t *testing.T) {
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "bad.json")
	os.WriteFile(cfgPath, []byte(`{invalid`), 0644)

	_, err := LoadConfig(cfgPath)
	if err == nil {
		t.Error("expected error for invalid JSON, got nil")
	}
}

func TestLoadConfigEnvOverrides(t *testing.T) {
	// Write a config file with base values.
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "config.json")
	os.WriteFile(cfgPath, []byte(`{"listen": ":443", "chapel_binary": "rj"}`), 0644)

	// Set env overrides.
	t.Setenv("RJ_GATEWAY_LISTEN", ":9090")
	t.Setenv("RJ_GATEWAY_SETEC_URL", "https://override.ts.net")
	t.Setenv("RJ_GATEWAY_CHAPEL_BIN", "/opt/bin/chapel")
	t.Setenv("TS_HOSTNAME", "override-host")
	t.Setenv("TS_STATE_DIR", "/override/state")

	cfg, err := LoadConfig(cfgPath)
	if err != nil {
		t.Fatal(err)
	}

	if cfg.Listen != ":9090" {
		t.Errorf("Listen = %q, want env override %q", cfg.Listen, ":9090")
	}
	if cfg.SetecURL != "https://override.ts.net" {
		t.Errorf("SetecURL = %q, want env override", cfg.SetecURL)
	}
	if cfg.ChapelBinary != "/opt/bin/chapel" {
		t.Errorf("ChapelBinary = %q, want env override", cfg.ChapelBinary)
	}
	if cfg.Tailscale.Hostname != "override-host" {
		t.Errorf("Tailscale.Hostname = %q, want env override", cfg.Tailscale.Hostname)
	}
	if cfg.Tailscale.StateDir != "/override/state" {
		t.Errorf("Tailscale.StateDir = %q, want env override", cfg.Tailscale.StateDir)
	}
}

func TestLoadConfigPartialFile(t *testing.T) {
	// Only override some fields; defaults should fill in the rest.
	dir := t.TempDir()
	cfgPath := filepath.Join(dir, "partial.json")
	os.WriteFile(cfgPath, []byte(`{"listen": ":8080"}`), 0644)

	cfg, err := LoadConfig(cfgPath)
	if err != nil {
		t.Fatal(err)
	}

	if cfg.Listen != ":8080" {
		t.Errorf("Listen = %q, want %q", cfg.Listen, ":8080")
	}
	// Defaults should be preserved for unset fields.
	if cfg.ChapelBinary != "remote-juggler" {
		t.Errorf("ChapelBinary = %q, want default", cfg.ChapelBinary)
	}
	if cfg.SetecPrefix != "remotejuggler/" {
		t.Errorf("SetecPrefix = %q, want default", cfg.SetecPrefix)
	}
}
