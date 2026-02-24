---
title: "MCP Server Integration"
description: "How to use RemoteJuggler as an MCP server for Claude Code and other AI coding assistants. Includes protocol details, all 36 tool definitions, and configuration."
category: "api"
llm_priority: 2
keywords:
  - mcp
  - server
  - claude-code
  - json-rpc
  - ai-assistant
  - credential-authority
---

# MCP Server

RemoteJuggler implements a Model Context Protocol (MCP) server for integration with Claude Code and other MCP-compatible tools.

## Overview

MCP is a JSON-RPC 2.0 based protocol that enables AI assistants to interact with external tools. RemoteJuggler's MCP server exposes 36 tools covering identity management, credential authority, security, and debugging.

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

---

## Identity Management Tools

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

---

## Security & GPG Tools

### juggler_gpg_status

Get GPG key status for all identities.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {}
}
```

---

### juggler_pin_store

Store an HSM PIN for hardware-backed credential operations.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "pin": {
      "type": "string",
      "description": "The PIN to store"
    }
  },
  "required": ["pin"]
}
```

---

### juggler_pin_clear

Clear the stored HSM PIN.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {}
}
```

---

### juggler_pin_status

Check HSM PIN availability status.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {}
}
```

---

### juggler_security_mode

Set the security mode for credential operations.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "mode": {
      "type": "string",
      "description": "Security mode to set"
    }
  },
  "required": ["mode"]
}
```

---

### juggler_setup

Run the interactive setup wizard.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "importSSH": {
      "type": "boolean",
      "description": "Import SSH hosts",
      "default": false
    },
    "importGPG": {
      "type": "boolean",
      "description": "Import GPG keys",
      "default": false
    }
  }
}
```

---

### juggler_tws_status

Get trusted workstation mode status.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {}
}
```

---

### juggler_tws_enable

Enable trusted workstation mode with TPM/Secure Enclave binding.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {}
}
```

---

## Token Management Tools

### juggler_token_verify

Verify token availability and validity for all identities.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {}
}
```

---

### juggler_token_get

Retrieve a stored token for an identity.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "identity": {
      "type": "string",
      "description": "Identity name"
    }
  },
  "required": ["identity"]
}
```

---

### juggler_token_clear

Clear a stored token for an identity.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "identity": {
      "type": "string",
      "description": "Identity name"
    }
  },
  "required": ["identity"]
}
```

---

## Configuration & Debug Tools

### juggler_config_show

Show the current configuration.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "section": {
      "type": "string",
      "description": "Configuration section to show"
    }
  }
}
```

---

### juggler_debug_ssh

Debug SSH configuration and connectivity.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {}
}
```

---

## KeePassXC Credential Authority Tools

These tools manage the KeePassXC-backed credential store (`~/.remotejuggler/keys.kdbx`).

### juggler_keys_init

Initialize the credential store database.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {}
}
```

---

### juggler_keys_status

Get credential store status (database path, lock state, entry count, HSM binding).

**Input Schema:**

```json
{
  "type": "object",
  "properties": {}
}
```

---

### juggler_keys_search

Fuzzy search credentials by title, username, URL, or notes.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "Search query (fuzzy matching with Levenshtein distance)"
    },
    "field": {
      "type": "string",
      "enum": ["title", "username", "url", "notes"],
      "description": "Search specific field only"
    },
    "group": {
      "type": "string",
      "description": "Filter by KeePassXC group"
    }
  },
  "required": ["query"]
}
```

---

### juggler_keys_resolve

Combined search + retrieve: find a credential and return its value.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "Search query to resolve"
    }
  },
  "required": ["query"]
}
```

---

### juggler_keys_get

Get a specific credential by exact title.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "title": {
      "type": "string",
      "description": "Credential title"
    }
  },
  "required": ["title"]
}
```

---

### juggler_keys_store

Store a new credential in the database.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "title": {
      "type": "string",
      "description": "Credential title"
    },
    "password": {
      "type": "string",
      "description": "The secret value to store"
    },
    "username": {
      "type": "string",
      "description": "Associated username"
    },
    "url": {
      "type": "string",
      "description": "Associated URL"
    },
    "group": {
      "type": "string",
      "description": "KeePassXC group"
    }
  },
  "required": ["title", "password"]
}
```

---

### juggler_keys_delete

Delete a credential from the database.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "title": {
      "type": "string",
      "description": "Credential title to delete"
    }
  },
  "required": ["title"]
}
```

---

### juggler_keys_list

List all credentials in the store.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "group": {
      "type": "string",
      "description": "Filter by KeePassXC group"
    }
  }
}
```

---

### juggler_keys_ingest_env

Ingest credentials from environment variables matching common patterns (`*_TOKEN`, `*_API_KEY`, `*_SECRET`, etc.).

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "pattern": {
      "type": "string",
      "description": "Custom glob pattern to match environment variables"
    }
  }
}
```

---

### juggler_keys_crawl_env

Crawl `.env` files for credentials and sync them to the store.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "path": {
      "type": "string",
      "description": "Root path to crawl for .env files"
    }
  }
}
```

Returns counts of added, updated, and deleted entries.

---

### juggler_keys_discover

Auto-discover credentials from all available sources (environment variables, SSH key metadata, `.env` files, provider CLI tokens).

**Input Schema:**

```json
{
  "type": "object",
  "properties": {}
}
```

---

### juggler_keys_export

Export credentials as environment variables or JSON.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "group": {
      "type": "string",
      "description": "Export only credentials from this group"
    },
    "format": {
      "type": "string",
      "enum": ["env", "json", "shell"],
      "description": "Output format",
      "default": "env"
    }
  }
}
```

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
      "version": "2.2.0"
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

## Client Configuration

### Claude Code

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

### Cursor

Add to `~/.cursor/mcp.json`:

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

### VS Code

Add to `~/.config/Code/User/mcp.json`:

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

### Windsurf

Add to `~/.windsurf/mcp.json`:

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
