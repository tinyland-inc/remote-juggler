package main

import (
	"context"
	"testing"
)

func TestResolverEnvSource(t *testing.T) {
	t.Setenv("TEST_SECRET_123", "env-value-abc")

	r := NewResolver(nil, nil, []string{"env"})
	result := r.Resolve(context.Background(), "TEST_SECRET_123", nil)

	if result.Value != "env-value-abc" {
		t.Errorf("Value = %q, want %q", result.Value, "env-value-abc")
	}
	if result.Source != "env" {
		t.Errorf("Source = %q, want %q", result.Source, "env")
	}
	if result.Error != "" {
		t.Errorf("Error = %q, want empty", result.Error)
	}
	if len(result.SourcesChecked) != 1 || result.SourcesChecked[0] != "env" {
		t.Errorf("SourcesChecked = %v, want [env]", result.SourcesChecked)
	}
}

func TestResolverEnvNotFound(t *testing.T) {
	r := NewResolver(nil, nil, []string{"env"})
	result := r.Resolve(context.Background(), "NONEXISTENT_SECRET_XYZ_999", nil)

	if result.Value != "" {
		t.Errorf("Value = %q, want empty", result.Value)
	}
	if result.Error == "" {
		t.Error("expected error, got empty")
	}
	if len(result.SourcesChecked) != 1 {
		t.Errorf("SourcesChecked = %v, want [env]", result.SourcesChecked)
	}
}

func TestResolverPrecedenceOrder(t *testing.T) {
	// env has the value; setec would be checked second but should not be reached.
	t.Setenv("PREC_TEST_KEY", "from-env")

	r := NewResolver(nil, nil, []string{"env", "setec"})
	result := r.Resolve(context.Background(), "PREC_TEST_KEY", nil)

	if result.Value != "from-env" {
		t.Errorf("Value = %q, want %q", result.Value, "from-env")
	}
	if result.Source != "env" {
		t.Errorf("Source = %q, want %q", result.Source, "env")
	}
	// Only env should have been checked (short-circuit on match).
	if len(result.SourcesChecked) != 1 {
		t.Errorf("SourcesChecked = %v, want [env] (short-circuit)", result.SourcesChecked)
	}
}

func TestResolverCustomSourcesOverride(t *testing.T) {
	// Default precedence is ["env", "sops", "kdbx", "setec"], but we pass
	// explicit sources to Resolve() which should override the defaults.
	t.Setenv("CUSTOM_SRC_KEY", "found-it")

	r := NewResolver(nil, nil, []string{"sops", "kdbx", "setec"})
	// Pass explicit sources that include "env" — should override the default.
	result := r.Resolve(context.Background(), "CUSTOM_SRC_KEY", []string{"env"})

	if result.Value != "found-it" {
		t.Errorf("Value = %q, want %q", result.Value, "found-it")
	}
	if result.Source != "env" {
		t.Errorf("Source = %q, want %q", result.Source, "env")
	}
}

func TestResolverUnknownSource(t *testing.T) {
	r := NewResolver(nil, nil, []string{"bogus"})
	result := r.Resolve(context.Background(), "anything", nil)

	if result.Value != "" {
		t.Errorf("Value = %q, want empty", result.Value)
	}
	if result.Error == "" {
		t.Error("expected error for unknown source, got empty")
	}
}

func TestResolverEmptySources(t *testing.T) {
	// Empty sources list should fall back to the resolver's configured precedence.
	t.Setenv("FALLBACK_KEY", "fallback-val")

	r := NewResolver(nil, nil, []string{"env"})
	result := r.Resolve(context.Background(), "FALLBACK_KEY", []string{})

	// Empty slice should use defaults.
	if result.Value != "fallback-val" {
		t.Errorf("Value = %q, want %q", result.Value, "fallback-val")
	}
}

func TestResolverMultipleSourcesFallthrough(t *testing.T) {
	// Unknown sources fail gracefully, then env succeeds.
	t.Setenv("MULTI_FALL_KEY", "env-wins")

	r := NewResolver(nil, nil, []string{"bogus1", "bogus2", "env"})
	result := r.Resolve(context.Background(), "MULTI_FALL_KEY", nil)

	if result.Value != "env-wins" {
		t.Errorf("Value = %q, want %q", result.Value, "env-wins")
	}
	if result.Source != "env" {
		t.Errorf("Source = %q, want %q", result.Source, "env")
	}
	// All three sources should have been checked.
	if len(result.SourcesChecked) != 3 {
		t.Errorf("SourcesChecked = %v, want 3 sources", result.SourcesChecked)
	}
}

func TestResolverAllSourcesFail(t *testing.T) {
	r := NewResolver(nil, nil, []string{"env", "bogus"})
	result := r.Resolve(context.Background(), "ABSOLUTELY_NOT_SET_EVER", nil)

	if result.Value != "" {
		t.Errorf("Value = %q, want empty", result.Value)
	}
	if result.Error == "" {
		t.Error("expected error when all sources fail")
	}
	if len(result.SourcesChecked) != 2 {
		t.Errorf("SourcesChecked = %v, want 2 sources", result.SourcesChecked)
	}
}
