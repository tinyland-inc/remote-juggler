#!/usr/bin/env bash
# Generate a GitHub App installation token from a private key.
#
# Requires: openssl, curl, jq
#
# Environment:
#   GITHUB_APP_ID           - GitHub App ID
#   GITHUB_APP_PRIVATE_KEY  - PEM-encoded private key (or path to file)
#   GITHUB_APP_INSTALL_ID   - Installation ID (optional; auto-detected if omitted)
#
# Usage:
#   eval "$(github-app-token.sh)"
#   # Sets GITHUB_TOKEN in the environment
#
# The token is valid for 1 hour. The JWT used to request it is valid for 10 minutes.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

: "${GITHUB_APP_ID:?GITHUB_APP_ID is required}"
: "${GITHUB_APP_PRIVATE_KEY:?GITHUB_APP_PRIVATE_KEY is required}"

# Resolve private key: if it looks like a path, read it; otherwise treat as PEM content.
if [[ -f "$GITHUB_APP_PRIVATE_KEY" ]]; then
    PRIVATE_KEY="$(cat "$GITHUB_APP_PRIVATE_KEY")"
else
    PRIVATE_KEY="$GITHUB_APP_PRIVATE_KEY"
fi

# Base64url encode (no padding, URL-safe).
b64url() {
    openssl base64 -A | tr '+/' '-_' | tr -d '='
}

# Build JWT header and payload.
NOW="$(date +%s)"
IAT=$((NOW - 60))   # 60s clock skew allowance
EXP=$((NOW + 600))  # 10 minute expiry

HEADER='{"alg":"RS256","typ":"JWT"}'
PAYLOAD="{\"iss\":\"${GITHUB_APP_ID}\",\"iat\":${IAT},\"exp\":${EXP}}"

HEADER_B64="$(echo -n "$HEADER" | b64url)"
PAYLOAD_B64="$(echo -n "$PAYLOAD" | b64url)"

# Sign with RS256.
SIGNATURE="$(echo -n "${HEADER_B64}.${PAYLOAD_B64}" \
    | openssl dgst -sha256 -sign <(echo "$PRIVATE_KEY") \
    | b64url)"

JWT="${HEADER_B64}.${PAYLOAD_B64}.${SIGNATURE}"

# If no installation ID provided, auto-detect the first one.
if [[ -z "${GITHUB_APP_INSTALL_ID:-}" ]]; then
    GITHUB_APP_INSTALL_ID="$(curl -sf \
        -H "Authorization: Bearer ${JWT}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/app/installations" \
        | jq -r '.[0].id')" \
        || die "failed to list installations"
    [[ "$GITHUB_APP_INSTALL_ID" != "null" ]] || die "no installations found"
fi

# Request installation access token.
TOKEN="$(curl -sf \
    -X POST \
    -H "Authorization: Bearer ${JWT}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/app/installations/${GITHUB_APP_INSTALL_ID}/access_tokens" \
    | jq -r '.token')" \
    || die "failed to create installation token"

[[ "$TOKEN" != "null" ]] || die "token response was null"

# Output for eval or export.
echo "export GITHUB_TOKEN=${TOKEN}"
