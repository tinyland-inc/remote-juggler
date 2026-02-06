#!/bin/bash
# RemoteJuggler Snippet Generator
# Extracts code snippets from source for DRY documentation
#
# Usage: ./scripts/generate-snippets.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$PROJECT_ROOT/docs/snippets"

echo "=== RemoteJuggler Snippet Generator ==="
echo ""

# Ensure snippets directory exists
mkdir -p "$DOCS_DIR"

# Extract tool schemas from Tools.chpl
echo "Extracting tool schemas..."

python3 << 'PYTHON'
import re
import json
import os

project_root = os.environ.get('PROJECT_ROOT', '.')
tools_file = os.path.join(project_root, 'src/remote_juggler/Tools.chpl')
output_file = os.path.join(project_root, 'docs/snippets/tool-schemas.json')

try:
    with open(tools_file, 'r') as f:
        content = f.read()
except FileNotFoundError:
    print(f"  Warning: {tools_file} not found")
    exit(0)

schemas = {}

# Pattern to match tool definitions
# Looking for: name = "tool_name" ... inputSchema = '{...}'
tool_pattern = r'new ToolDefinition\(\s*name\s*=\s*"([^"]+)".*?inputSchema\s*=\s*\'([^\']+(?:\'[^\']*\'[^\']*)*)\''

for match in re.finditer(tool_pattern, content, re.DOTALL):
    name = match.group(1)
    # Reconstruct the schema from concatenated strings
    schema_raw = match.group(2)
    # Remove string concatenation artifacts
    schema_clean = re.sub(r"'\s*\+\s*'", "", schema_raw)
    schema_clean = schema_clean.replace("' +", "").replace("+ '", "")

    try:
        schema = json.loads(schema_clean)
        schemas[name] = schema
        print(f"  Extracted: {name}")
    except json.JSONDecodeError as e:
        print(f"  Warning: Could not parse schema for {name}: {e}")

if schemas:
    with open(output_file, 'w') as f:
        json.dump(schemas, f, indent=2)
    print(f"  Wrote {len(schemas)} schemas to {output_file}")
else:
    print("  No schemas extracted")
PYTHON

# Generate CLI help if binary exists
echo ""
echo "Generating CLI help..."

BINARY="$PROJECT_ROOT/target/release/remote-juggler"
if [ ! -f "$BINARY" ]; then
    BINARY="$PROJECT_ROOT/target/debug/remote-juggler"
fi

if [ -f "$BINARY" ]; then
    "$BINARY" --help > "$DOCS_DIR/cli-help.txt" 2>/dev/null || true
    echo "  Wrote CLI help to docs/snippets/cli-help.txt"
else
    echo "  Warning: Binary not found, skipping CLI help generation"
    echo "  Run 'just build' or 'just release' first"
fi

# Copy example configuration
echo ""
echo "Copying example configuration..."

EXAMPLE_CONFIG=$(cat << 'EOF'
{
  "$schema": "https://remote-juggler.dev/schema/v2.json",
  "version": "2.0.0",
  "identities": {
    "gitlab-work": {
      "provider": "gitlab",
      "host": "gitlab-work",
      "hostname": "gitlab.com",
      "user": "Work User",
      "email": "work@company.com",
      "gpg": {
        "keyId": "ABC123DEF456",
        "signCommits": true
      }
    },
    "gitlab-personal": {
      "provider": "gitlab",
      "host": "gitlab-personal",
      "hostname": "gitlab.com",
      "user": "Personal User",
      "email": "personal@email.com"
    }
  },
  "settings": {
    "defaultProvider": "gitlab",
    "autoDetect": true,
    "useKeychain": true,
    "gpgSign": true,
    "fallbackToSSH": true
  },
  "state": {
    "currentIdentity": "",
    "lastSwitch": ""
  }
}
EOF
)

echo "$EXAMPLE_CONFIG" > "$DOCS_DIR/config-example.json"
echo "  Wrote example config to docs/snippets/config-example.json"

# Generate MCP initialization example
echo ""
echo "Generating MCP examples..."

MCP_INIT=$(cat << 'EOF'
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-11-25",
    "capabilities": {},
    "clientInfo": {
      "name": "example-client",
      "version": "1.0.0"
    }
  }
}
EOF
)

echo "$MCP_INIT" > "$DOCS_DIR/mcp-init.json"
echo "  Wrote MCP init example to docs/snippets/mcp-init.json"

# Summary
echo ""
echo "=== Snippet Generation Complete ==="
echo ""
echo "Generated files:"
ls -la "$DOCS_DIR/"
