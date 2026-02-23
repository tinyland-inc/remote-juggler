#!/usr/bin/env bash
# =============================================================================
# OpenTofu wrapper that resolves secrets via rj-gateway before running tofu.
#
# Usage:
#   ./apply.sh init
#   ./apply.sh plan
#   ./apply.sh apply
#   ./apply.sh destroy
#   ./apply.sh output
#
# Secrets are resolved from rj-gateway's composite resolver, dogfooding
# the same credential pipeline that the infrastructure manages.
#
# Override the gateway URL:
#   RJ_GATEWAY_URL=https://rj-gateway.example.ts.net ./apply.sh plan
# =============================================================================
set -euo pipefail

GATEWAY="${RJ_GATEWAY_URL:-http://localhost:8443}"

resolve() {
  local result
  result=$(curl -sf -X POST "$GATEWAY/resolve" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$1\"}" 2>/dev/null | jq -r '.value') || {
    echo "ERROR: Failed to resolve '$1' from gateway at $GATEWAY" >&2
    echo "       Is rj-gateway running? Try: just gateway-run" >&2
    exit 1
  }

  if [ -z "$result" ] || [ "$result" = "null" ]; then
    echo "ERROR: Empty result resolving '$1'" >&2
    exit 1
  fi

  echo "$result"
}

echo "Resolving secrets from rj-gateway ($GATEWAY)..."

export TF_VAR_tailscale_oauth_client_id=$(resolve "tailscale-oauth-client-id")
export TF_VAR_tailscale_oauth_client_secret=$(resolve "tailscale-oauth-client-secret")
export TF_VAR_tailscale_auth_key=$(resolve "tailscale-auth-key")
export TF_VAR_civo_token=$(resolve "civo-token")
export AWS_ACCESS_KEY_ID=$(resolve "civo-object-storage-key")
export AWS_SECRET_ACCESS_KEY=$(resolve "civo-object-storage-secret")

# Agent credentials (seeded into Setec for runtime resolution)
export TF_VAR_github_token=$(resolve "github-token" 2>/dev/null || echo "")
export TF_VAR_gitlab_token=$(resolve "gitlab-token" 2>/dev/null || echo "")
export TF_VAR_anthropic_api_key=$(resolve "anthropic-api-key" 2>/dev/null || echo "")
export TF_VAR_ghcr_token=$(resolve "ghcr-token")

echo "Secrets resolved. Running: tofu $*"

cd "$(dirname "$0")"
exec tofu "$@"
