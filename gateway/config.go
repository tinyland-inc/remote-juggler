package main

import (
	"encoding/json"
	"os"
)

// Config holds the gateway configuration.
type Config struct {
	// Listen is the address to listen on. Use "local" to skip tsnet.
	Listen string `json:"listen"`
	// InClusterListen is an optional second listener for in-cluster HTTP (no TLS).
	// When set (e.g. ":8080"), the gateway serves the same routes over plain HTTP
	// alongside the tsnet TLS listener, allowing pods without tailnet access to
	// reach the gateway via a K8s Service.
	InClusterListen string          `json:"in_cluster_listen"`
	ChapelBinary    string          `json:"chapel_binary"`
	SetecURL        string          `json:"setec_url"`
	SetecPrefix     string          `json:"setec_prefix"`
	SetecSecrets    []string        `json:"setec_secrets"`
	Precedence      []string        `json:"precedence"`
	ApertureURL     string          `json:"aperture_url"`
	Tailscale       TailscaleConfig `json:"tailscale"`
}

// TailscaleConfig holds Tailscale-specific settings.
type TailscaleConfig struct {
	AuthKey  string `json:"auth_key"`
	Hostname string `json:"hostname"`
	StateDir string `json:"state_dir"`
}

// DefaultConfig returns the default gateway configuration.
func DefaultConfig() Config {
	return Config{
		Listen:       ":443",
		ChapelBinary: "remote-juggler",
		SetecURL:     "",
		SetecPrefix:  "remotejuggler/",
		SetecSecrets: nil,
		Precedence:   []string{"env", "sops", "kdbx", "setec"},
		Tailscale: TailscaleConfig{
			Hostname: "rj-gateway",
		},
	}
}

// LoadConfig reads configuration from a JSON file, then applies
// environment variable overrides.
func LoadConfig(path string) (Config, error) {
	cfg := DefaultConfig()

	if path != "" {
		data, err := os.ReadFile(path)
		if err != nil {
			return cfg, err
		}
		if err := json.Unmarshal(data, &cfg); err != nil {
			return cfg, err
		}
	}

	// Environment overrides take highest precedence.
	if v := os.Getenv("RJ_GATEWAY_LISTEN"); v != "" {
		cfg.Listen = v
	}
	if v := os.Getenv("RJ_GATEWAY_SETEC_URL"); v != "" {
		cfg.SetecURL = v
	}
	if v := os.Getenv("RJ_GATEWAY_CHAPEL_BIN"); v != "" {
		cfg.ChapelBinary = v
	}
	if v := os.Getenv("TS_HOSTNAME"); v != "" {
		cfg.Tailscale.Hostname = v
	}
	if v := os.Getenv("TS_STATE_DIR"); v != "" {
		cfg.Tailscale.StateDir = v
	}
	if v := os.Getenv("RJ_GATEWAY_APERTURE_URL"); v != "" {
		cfg.ApertureURL = v
	}
	if v := os.Getenv("RJ_GATEWAY_IN_CLUSTER_LISTEN"); v != "" {
		cfg.InClusterListen = v
	}

	return cfg, nil
}
