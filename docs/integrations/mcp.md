---
title: "MCP Server Integration"
description: "How to use RemoteJuggler as an MCP server for Claude Code and other AI coding assistants. Includes protocol details, tool definitions, and configuration."
category: "api"
llm_priority: 2
keywords:
  - mcp
  - server
  - claude-code
  - json-rpc
  - ai-assistant
---

# MCP Server

RemoteJuggler implements a Model Context Protocol (MCP) server for integration with Claude Code and other MCP-compatible tools.

## Overview

MCP is a JSON-RPC 2.0 based protocol that enables AI assistants to interact with external tools. RemoteJuggler's MCP server exposes git identity management tools.

**Implementation:** `src/remote_juggler/MCP.chpl`

## Starting the Server

```bash
remote-juggler --mode=mcp
```

The server reads JSON-RPC messages from stdin and writes responses to stdout.

## Protocol Version

RemoteJuggler supports MCP protocol version `2025-11-25`.

## Capabilities

The server advertises the following capabilities:

```json
{
  "capabilities": {
    "tools": {}
  }
}
```

## Tool Definitions

### juggler_list_identities

List all configured git identities.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "provider": {
      "type": "string",
      "enum": ["gitlab", "github", "bitbucket", "all"],
      "description": "Filter identities by provider type"
    },
    "includeCredentialStatus": {
      "type": "boolean",
      "description": "Include credential availability status",
      "default": false
    }
  }
}
```

**Implementation:** `src/remote_juggler/Tools.chpl`

---

### juggler_detect_identity

Detect the git identity for a repository based on its remote URL.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "repoPath": {
      "type": "string",
      "description": "Path to the git repository. Defaults to current working directory."
    }
  }
}
```

**Implementation:** `src/remote_juggler/Tools.chpl`

---

### juggler_switch

Switch to a different git identity context.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "identity": {
      "type": "string",
      "description": "Identity name to switch to"
    },
    "setRemote": {
      "type": "boolean",
      "description": "Update git remote URL to match identity's SSH host alias",
      "default": true
    },
    "configureGPG": {
      "type": "boolean",
      "description": "Configure GPG signing using the identity's GPG key",
      "default": true
    },
    "repoPath": {
      "type": "string",
      "description": "Path to git repository. Defaults to current working directory."
    }
  },
  "required": ["identity"]
}
```

**Implementation:** `src/remote_juggler/Tools.chpl`

---

### juggler_status

Get current git identity context and authentication status.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "repoPath": {
      "type": "string",
      "description": "Path to git repository for context"
    },
    "verbose": {
      "type": "boolean",
      "description": "Include additional details like SSH key fingerprints",
      "default": false
    }
  }
}
```

**Implementation:** `src/remote_juggler/Tools.chpl`

---

### juggler_validate

Validate SSH key connectivity and credential availability.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "identity": {
      "type": "string",
      "description": "Identity name to validate"
    },
    "checkGPG": {
      "type": "boolean",
      "description": "Verify GPG key exists and is registered with provider",
      "default": false
    },
    "testAuth": {
      "type": "boolean",
      "description": "Test authentication by making an API call",
      "default": true
    }
  },
  "required": ["identity"]
}
```

**Implementation:** `src/remote_juggler/Tools.chpl`

---

### juggler_store_token

Store a token in the system keychain.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "identity": {
      "type": "string",
      "description": "Identity name to store the token for"
    },
    "token": {
      "type": "string",
      "description": "The access token to store"
    }
  },
  "required": ["identity", "token"]
}
```

**Implementation:** `src/remote_juggler/Tools.chpl`

---

### juggler_sync_config

Synchronize managed configuration blocks.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "force": {
      "type": "boolean",
      "description": "Force sync even if no changes detected",
      "default": false
    },
    "dryRun": {
      "type": "boolean",
      "description": "Show what would be changed without making changes",
      "default": false
    }
  }
}
```

**Implementation:** `src/remote_juggler/Tools.chpl`

---

## Example Session

### Initialize

Request:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-11-25",
    "capabilities": {},
    "clientInfo": {
      "name": "claude-code",
      "version": "1.0.0"
    }
  }
}
```

Response:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2025-11-25",
    "capabilities": {
      "tools": {}
    },
    "serverInfo": {
      "name": "remote-juggler",
      "version": "2.0.0"
    }
  }
}
```

### List Tools

Request:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list"
}
```

### Call Tool

Request:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "juggler_detect_identity",
    "arguments": {
      "repoPath": "/home/user/project"
    }
  }
}
```

Response:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Detected Identity: gitlab-work\nProvider: gitlab\nConfidence: high"
      }
    ]
  }
}
```

## Claude Code Configuration

### Global Configuration

Add to `~/.claude/mcp.json`:

```json
{
  "mcpServers": {
    "remote-juggler": {
      "command": "remote-juggler",
      "args": ["--mode=mcp"]
    }
  }
}
```

### Slash Commands

The installer creates slash commands in `~/.claude/commands/`:

**`/juggle`** - Switch identity:
```markdown
---
description: Switch git identity context using RemoteJuggler
allowed-tools: "Bash(...), Read(...)"
---

Switch to the requested git identity context.
Arguments: $ARGUMENTS (identity name)
```

**`/identity`** - Manage identities:
```markdown
---
description: Show or manage git identities with RemoteJuggler
allowed-tools: "Bash(...), Read(...)"
---

Usage:
- /identity list
- /identity detect
- /identity validate <name>
```

## Debugging

Enable debug logging:

```bash
REMOTE_JUGGLER_VERBOSE=1 remote-juggler --mode=mcp 2>mcp-debug.log
```

View server stderr output in `mcp-debug.log`.
