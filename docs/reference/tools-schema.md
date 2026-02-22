---
title: "MCP Tool Schemas"
description: "JSON Schema definitions for core RemoteJuggler MCP tools including identity management, GPG signing, security mode, and setup tools. See Tools.chpl for the complete set of 36 tool definitions."
category: "api"
llm_priority: 1
keywords:
  - mcp
  - tools
  - api
  - json-rpc
  - schema
  - gpg
---

# MCP Tool Schemas

JSON schemas for RemoteJuggler MCP tools.

Source: `src/remote_juggler/Tools.chpl`

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

## juggler_pin_store

Store YubiKey PIN in hardware security module (TPM/SecureEnclave).

### Schema

```json
{
  "name": "juggler_pin_store",
  "description": "Store a YubiKey PIN in hardware security module (TPM 2.0 on Linux, Secure Enclave on macOS). Enables passwordless GPG signing in trusted_workstation mode.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "identity": {
        "type": "string",
        "description": "Identity name to store PIN for"
      },
      "pin": {
        "type": "string",
        "description": "YubiKey PIN (6-127 characters)"
      }
    },
    "required": ["identity", "pin"]
  }
}
```

### Example

```json
{
  "name": "juggler_pin_store",
  "arguments": {
    "identity": "work",
    "pin": "123456"
  }
}
```

---

## juggler_pin_clear

Remove stored PIN from hardware security module.

### Schema

```json
{
  "name": "juggler_pin_clear",
  "description": "Remove stored PIN from hardware security module. Use when rotating PINs or disabling trusted_workstation mode.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "identity": {
        "type": "string",
        "description": "Identity name to clear PIN for"
      }
    },
    "required": ["identity"]
  }
}
```

### Example

```json
{
  "name": "juggler_pin_clear",
  "arguments": {
    "identity": "work"
  }
}
```

---

## juggler_pin_status

Check PIN storage status in hardware security module.

### Schema

```json
{
  "name": "juggler_pin_status",
  "description": "Check PIN storage status in hardware security module. Returns HSM availability, stored identities, and current security mode.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "identity": {
        "type": "string",
        "description": "Check specific identity (omit for all identities)"
      }
    }
  }
}
```

### Example

```json
{
  "name": "juggler_pin_status",
  "arguments": {}
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `hsmAvailable` | boolean | Whether HSM is available |
| `hsmType` | string | "tpm", "secure_enclave", "keychain", or "none" |
| `securityMode` | string | Current security mode |
| `storedIdentities` | array | List of identities with stored PINs |

---

## juggler_security_mode

Get or set the security mode for GPG signing operations.

### Schema

```json
{
  "name": "juggler_security_mode",
  "description": "Get or set the security mode for GPG signing operations. Controls how YubiKey PINs are handled during signing.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "mode": {
        "type": "string",
        "enum": ["maximum_security", "developer_workflow", "trusted_workstation"],
        "description": "Security mode to set. Omit to get current mode."
      }
    }
  }
}
```

### Security Modes

| Mode | Description |
|------|-------------|
| `maximum_security` | PIN required for every signing operation |
| `developer_workflow` | PIN cached by gpg-agent (default TTL) |
| `trusted_workstation` | PIN stored in HSM, retrieved automatically |

### Example

```json
{
  "name": "juggler_security_mode",
  "arguments": {
    "mode": "trusted_workstation"
  }
}
```

---

## juggler_setup

Run first-time setup wizard.

### Schema

```json
{
  "name": "juggler_setup",
  "description": "Run first-time setup wizard. Detects SSH hosts, GPG keys, and YubiKey devices to auto-configure identities.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "mode": {
        "type": "string",
        "enum": ["auto", "status", "import_ssh", "import_gpg"],
        "description": "Setup mode (default: auto)",
        "default": "auto"
      },
      "force": {
        "type": "boolean",
        "description": "Overwrite existing configuration",
        "default": false
      }
    }
  }
}
```

### Setup Modes

| Mode | Description |
|------|-------------|
| `auto` | Full automatic setup (SSH + GPG + HSM detection) |
| `status` | Show current setup status without changes |
| `import_ssh` | Import identities from SSH config only |
| `import_gpg` | Associate GPG keys with existing identities |

### Example

```json
{
  "name": "juggler_setup",
  "arguments": {
    "mode": "auto",
    "force": false
  }
}
```

---

## juggler_gpg_status

Check GPG/SSH signing readiness including hardware token status.

### Schema

```json
{
  "name": "juggler_gpg_status",
  "description": "Check GPG/SSH signing readiness including hardware token (YubiKey) status. Returns whether signing is possible, touch requirements, and actionable guidance for agents.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "identity": {
        "type": "string",
        "description": "Identity to check signing status for. If omitted, checks current repository context."
      },
      "repoPath": {
        "type": "string",
        "description": "Path to git repository for context. Defaults to current working directory."
      }
    }
  }
}
```

### Example

```json
{
  "name": "juggler_gpg_status",
  "arguments": {
    "identity": "gitlab-personal"
  }
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `identity` | string | Identity being checked |
| `signingFormat` | string | "gpg" or "ssh" |
| `keyId` | string | GPG key ID or SSH key path |
| `hardwareKey` | boolean | Whether key is on hardware token |
| `cardPresent` | boolean | Whether YubiKey is connected |
| `cardSerial` | string | YubiKey serial number |
| `touchPolicy` | object | Touch policies for sig/enc/aut |
| `canSign` | boolean | Whether automated signing is possible |
| `reason` | string | Why signing may not be possible |
| `recommendation` | string | Guidance for agents |

### Use Cases

1. **Pre-commit check**: Call before attempting signed commits to verify hardware token is ready
2. **Identity validation**: Verify signing configuration is complete
3. **User guidance**: Get actionable recommendations for signing setup

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
