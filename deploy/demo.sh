#!/usr/bin/env bash
# RemoteJuggler Gateway Demo
# Demonstrates the full credential resolution flow:
#   AI agent -> Aperture -> rj-gateway -> composite resolution
#
# Prerequisites:
#   1. rj-gateway running (locally or on tailnet)
#   2. remote-juggler binary in PATH
#
# Usage:
#   ./deploy/demo.sh [gateway-url]
#   ./deploy/demo.sh                          # defaults to localhost:8443
#   ./deploy/demo.sh https://rj-gateway.ts.net  # tailnet
set -euo pipefail

GATEWAY="${1:-http://localhost:8443}"

echo "=== RemoteJuggler Gateway Demo ==="
echo "Gateway: $GATEWAY"
echo ""

# 1. Health check
echo "--- Health Check ---"
curl -s "$GATEWAY/health" | jq .
echo ""

# 2. List all MCP tools (should include gateway-injected tools)
echo "--- MCP Tools (via gateway) ---"
TOOLS=$(curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}')
echo "$TOOLS" | jq '.result.tools | length' | xargs -I{} echo "Total tools: {}"
echo "$TOOLS" | jq -r '.result.tools[].name' | grep juggler_ | sort
echo ""

# 3. Composite resolution - try resolving a common credential
echo "--- Composite Resolution ---"
echo "Resolving DATABASE_URL from all sources..."
curl -s -X POST "$GATEWAY/resolve" \
  -H "Content-Type: application/json" \
  -d '{"query": "DATABASE_URL"}' | jq .
echo ""

# 4. MCP tool call - resolve via JSON-RPC
echo "--- MCP Tool: juggler_resolve_composite ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "juggler_resolve_composite",
      "arguments": {
        "query": "GITHUB_TOKEN",
        "sources": ["env", "kdbx", "setec"]
      }
    }
  }' | jq .
echo ""

# 5. Check Setec connectivity
echo "--- Setec Secret List ---"
curl -s "$GATEWAY/setec/list" | jq .
echo ""

# 6. View audit log
echo "--- Audit Log (last 5 entries) ---"
curl -s "$GATEWAY/audit" | jq '.entries[:5]'
echo ""

# 7. MCP tool call - audit log via JSON-RPC
echo "--- MCP Tool: juggler_audit_log ---"
curl -s -X POST "$GATEWAY/mcp" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "juggler_audit_log",
      "arguments": {"count": 5}
    }
  }' | jq '.result'
echo ""

echo "=== Demo Complete ==="
echo ""
echo "To use with Claude Code, add to .mcp.json:"
echo '  "rj-gateway": {'
echo '    "url": "'$GATEWAY'/mcp",'
echo '    "transport": "http"'
echo '  }'
