---
title: "MCP Tool Schemas"
description: "Complete JSON Schema definitions for all RemoteJuggler MCP tools including juggler_switch, juggler_status, juggler_validate, juggler_list_identities, and more."
category: "api"
llm_priority: 1
keywords:
  - mcp
  - tools
  - api
  - json-rpc
  - schema
---

# MCP Tool Schemas

JSON schemas for RemoteJuggler MCP tools.

Source: `src/remote_juggler/Tools.chpl:52-209`

## juggler_list_identities

List all configured git identities.

### Schema

```json
{
  "name": "juggler_list_identities",
  "description": "List all configured git identities with their providers (GitLab, GitHub, Bitbucket, etc.). Optionally filter by provider and include credential availability status.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "provider": {
        "type": "string",
        "enum": ["gitlab", "github", "bitbucket", "all"],
        "description": "Filter identities by provider type. Use 'all' or omit for all providers."
      },
      "includeCredentialStatus": {
        "type": "boolean",
        "description": "Include credential availability status (keychain, env, CLI) for each identity",
        "default": false
      }
    }
  }
}
```

### Example

```json
{
  "name": "juggler_list_identities",
  "arguments": {
    "provider": "gitlab",
    "includeCredentialStatus": true
  }
}
```

---

## juggler_detect_identity

Detect the git identity for a repository.

### Schema

```json
{
  "name": "juggler_detect_identity",
  "description": "Detect the git identity for a repository based on its remote URL. Analyzes SSH host aliases, gitconfig URL rewrites, and organization paths to determine the appropriate identity.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "repoPath": {
        "type": "string",
        "description": "Path to the git repository. Defaults to current working directory if not specified."
      }
    }
  }
}
```

### Example

```json
{
  "name": "juggler_detect_identity",
  "arguments": {
    "repoPath": "/home/user/projects/my-app"
  }
}
```

---

## juggler_switch

Switch to a different git identity.

### Schema

```json
{
  "name": "juggler_switch",
  "description": "Switch to a different git identity context. Updates git user config, authenticates with provider CLI (glab/gh) if available, and optionally configures GPG signing.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "identity": {
        "type": "string",
        "description": "Identity name to switch to (e.g., 'personal', 'work', 'github-personal')"
      },
      "setRemote": {
        "type": "boolean",
        "description": "Update git remote URL to match the identity's SSH host alias",
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
}
```

### Example

```json
{
  "name": "juggler_switch",
  "arguments": {
    "identity": "work",
    "setRemote": true,
    "configureGPG": true
  }
}
```

---

## juggler_status

Get current git identity status.

### Schema

```json
{
  "name": "juggler_status",
  "description": "Get the current git identity context, authentication status, GPG configuration, and recent switch history. Provides a comprehensive view of the current identity state.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "repoPath": {
        "type": "string",
        "description": "Path to git repository for context. Defaults to current working directory."
      },
      "verbose": {
        "type": "boolean",
        "description": "Include additional details like SSH key fingerprints and credential sources",
        "default": false
      }
    }
  }
}
```

### Example

```json
{
  "name": "juggler_status",
  "arguments": {
    "verbose": true
  }
}
```

---

## juggler_validate

Validate identity connectivity.

### Schema

```json
{
  "name": "juggler_validate",
  "description": "Validate SSH key connectivity and credential availability for an identity. Tests the SSH connection to the provider and verifies token accessibility.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "identity": {
        "type": "string",
        "description": "Identity name to validate (e.g., 'personal', 'work')"
      },
      "checkGPG": {
        "type": "boolean",
        "description": "Also verify GPG key exists and is registered with the provider",
        "default": false
      },
      "testAuth": {
        "type": "boolean",
        "description": "Test authentication by making an API call to the provider",
        "default": true
      }
    },
    "required": ["identity"]
  }
}
```

### Example

```json
{
  "name": "juggler_validate",
  "arguments": {
    "identity": "work",
    "checkGPG": true,
    "testAuth": true
  }
}
```

---

## juggler_store_token

Store token in Keychain.

### Schema

```json
{
  "name": "juggler_store_token",
  "description": "Store a token in the system keychain (macOS) or credential store for an identity. The token will be used for provider CLI authentication.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "identity": {
        "type": "string",
        "description": "Identity name to store the token for"
      },
      "token": {
        "type": "string",
        "description": "The access token to store (GitLab/GitHub personal access token)"
      }
    },
    "required": ["identity", "token"]
  }
}
```

### Example

```json
{
  "name": "juggler_store_token",
  "arguments": {
    "identity": "work",
    "token": "glpat-xxxxxxxxxxxxxxxxxxxx"
  }
}
```

---

## juggler_sync_config

Synchronize configuration.

### Schema

```json
{
  "name": "juggler_sync_config",
  "description": "Synchronize managed configuration blocks from SSH config and gitconfig. Updates the RemoteJuggler config file with the latest SSH hosts and URL rewrites.",
  "inputSchema": {
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
}
```

### Example

```json
{
  "name": "juggler_sync_config",
  "arguments": {
    "dryRun": true
  }
}
```

---

## Tool Call Format

All tools are called via MCP `tools/call` method:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "juggler_switch",
    "arguments": {
      "identity": "work"
    }
  }
}
```

Response format:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Switched to identity: work\n..."
      }
    ]
  }
}
```
