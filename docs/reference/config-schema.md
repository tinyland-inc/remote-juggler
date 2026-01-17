---
title: "Configuration Schema"
description: "Full config.json schema reference with identity definitions, GPG settings, credential sources, and global settings."
category: "config"
llm_priority: 1
keywords:
  - config
  - json
  - schema
  - identities
  - settings
---

# Configuration Schema

Reference for the RemoteJuggler configuration file format.

## File Location

Default: `~/.config/remote-juggler/config.json`

Override: `--configPath=<path>` or `REMOTE_JUGGLER_CONFIG` environment variable.

## Schema Version

Current schema version: `2.0.0`

```json
{
  "$schema": "https://remote-juggler.dev/schema/v2.json",
  "version": "2.0.0"
}
```

## Top-Level Structure

```json
{
  "$schema": "string",
  "version": "string",
  "identities": { ... },
  "settings": { ... },
  "state": { ... }
}
```

## Identities Object

Map of identity name to identity configuration.

### Identity Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `provider` | string | Yes | One of: `gitlab`, `github`, `bitbucket`, `custom` |
| `host` | string | Yes | SSH host alias (e.g., `gitlab-work`) |
| `hostname` | string | Yes | Actual hostname (e.g., `gitlab.com`) |
| `user` | string | Yes | Git user.name for commits |
| `email` | string | Yes | Git user.email for commits |
| `identityFile` | string | No | Path to SSH private key |
| `tokenEnvVar` | string | No | Environment variable containing API token |
| `credentialSource` | string | No | One of: `keychain`, `environment`, `cli`, `none` |
| `gpg` | object | No | GPG signing configuration |

### GPG Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `keyId` | string | `""` | GPG key ID (short or long form) |
| `signCommits` | boolean | `false` | Automatically sign commits |
| `signTags` | boolean | `false` | Automatically sign tags |
| `autoSignoff` | boolean | `false` | Add Signed-off-by line |

### Example Identity

```json
{
  "identities": {
    "gitlab-work": {
      "provider": "gitlab",
      "host": "gitlab-work",
      "hostname": "gitlab.com",
      "user": "Work User",
      "email": "work@company.com",
      "identityFile": "~/.ssh/id_ed25519_work",
      "tokenEnvVar": "GITLAB_WORK_TOKEN",
      "gpg": {
        "keyId": "ABC123DEF456",
        "signCommits": true,
        "signTags": true,
        "autoSignoff": false
      }
    }
  }
}
```

## Settings Object

Global settings controlling RemoteJuggler behavior.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `defaultProvider` | string | `"gitlab"` | Default provider for new identities |
| `autoDetect` | boolean | `true` | Auto-detect identity from repository |
| `useKeychain` | boolean | `true` | Use macOS Keychain for tokens |
| `gpgSign` | boolean | `true` | Enable GPG signing features |
| `gpgVerifyWithProvider` | boolean | `false` | Verify GPG keys with provider API |
| `fallbackToSSH` | boolean | `true` | Allow SSH-only mode when no token |
| `verboseLogging` | boolean | `false` | Enable debug output |

### Example Settings

```json
{
  "settings": {
    "defaultProvider": "gitlab",
    "autoDetect": true,
    "useKeychain": true,
    "gpgSign": true,
    "gpgVerifyWithProvider": false,
    "fallbackToSSH": true,
    "verboseLogging": false
  }
}
```

## State Object

Runtime state tracking.

| Field | Type | Description |
|-------|------|-------------|
| `currentIdentity` | string | Name of currently active identity |
| `lastSwitch` | string | ISO 8601 timestamp of last switch |

### Example State

```json
{
  "state": {
    "currentIdentity": "gitlab-work",
    "lastSwitch": "2026-01-15T10:30:00Z"
  }
}
```

## Complete Example

```json
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
      "identityFile": "~/.ssh/id_ed25519_work",
      "gpg": {
        "keyId": "ABC123DEF456",
        "signCommits": true,
        "signTags": true,
        "autoSignoff": false
      }
    },
    "gitlab-personal": {
      "provider": "gitlab",
      "host": "gitlab-personal",
      "hostname": "gitlab.com",
      "user": "Personal User",
      "email": "personal@email.com",
      "identityFile": "~/.ssh/id_ed25519_personal"
    },
    "github-oss": {
      "provider": "github",
      "host": "github.com",
      "hostname": "github.com",
      "user": "GitHub User",
      "email": "github@email.com",
      "identityFile": "~/.ssh/id_ed25519_github",
      "gpg": {
        "keyId": "XYZ789ABC123",
        "signCommits": true,
        "signTags": true,
        "autoSignoff": false
      }
    }
  },
  "settings": {
    "defaultProvider": "gitlab",
    "autoDetect": true,
    "useKeychain": true,
    "gpgSign": true,
    "gpgVerifyWithProvider": false,
    "fallbackToSSH": true,
    "verboseLogging": false
  },
  "state": {
    "currentIdentity": "gitlab-work",
    "lastSwitch": "2026-01-15T10:30:00Z"
  }
}
```

## Validation

### Required Fields

- At least one identity must be configured
- Each identity must have: `provider`, `host`, `hostname`, `user`, `email`

### Constraints

- `provider` must be one of: `gitlab`, `github`, `bitbucket`, `custom`
- `email` must be a valid email format
- `host` should match an SSH config Host entry
- `keyId` should be a valid GPG key ID if specified

### JSON Validation

Validate your config:

```bash
cat ~/.config/remote-juggler/config.json | python -m json.tool
```

Or use the CLI:

```bash
remote-juggler config show
```

Errors are reported if the config is invalid.
