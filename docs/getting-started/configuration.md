---
title: "Configuration"
description: "Configuration file format, identity settings, GPG configuration, and managed configuration blocks."
category: "config"
llm_priority: 2
keywords:
  - config
  - settings
  - identities
  - json
  - gpg
---

# Configuration

RemoteJuggler stores configuration in JSON format at `~/.config/remote-juggler/config.json`.

## Configuration Schema

The configuration file structure (see `install.sh:173-191`):

```json
{
  "$schema": "https://remote-juggler.dev/schema/v2.json",
  "version": "2.0.0",
  "identities": {},
  "settings": {
    "defaultProvider": "gitlab",
    "autoDetect": true,
    "useKeychain": true,
    "gpgSign": true,
    "fallbackToSSH": true,
    "verboseLogging": false
  },
  "state": {
    "currentIdentity": "",
    "lastSwitch": ""
  }
}
```

## Identity Configuration

Each identity is keyed by name and contains:

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

### Identity Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `provider` | string | Yes | `gitlab`, `github`, `bitbucket`, or `custom` |
| `host` | string | Yes | SSH host alias (matches `Host` in SSH config) |
| `hostname` | string | Yes | Actual hostname (e.g., `gitlab.com`) |
| `user` | string | Yes | Git user.name for commits |
| `email` | string | Yes | Git user.email for commits |
| `identityFile` | string | No | Path to SSH private key |
| `tokenEnvVar` | string | No | Environment variable containing API token |
| `gpg` | object | No | GPG signing configuration |

### GPG Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `keyId` | string | `""` | GPG key ID for signing |
| `signCommits` | bool | `false` | Auto-sign commits |
| `signTags` | bool | `false` | Auto-sign tags |
| `autoSignoff` | bool | `false` | Add Signed-off-by line |

## Settings

Global settings control RemoteJuggler behavior:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `defaultProvider` | string | `"gitlab"` | Default provider for new identities |
| `autoDetect` | bool | `true` | Auto-detect identity from repository |
| `useKeychain` | bool | `true` | Use macOS Keychain for tokens |
| `gpgSign` | bool | `true` | Enable GPG signing features |
| `gpgVerifyWithProvider` | bool | `false` | Verify GPG keys with provider API |
| `fallbackToSSH` | bool | `true` | Allow SSH-only mode when no token |
| `verboseLogging` | bool | `false` | Enable debug output |

## State Tracking

The `state` section tracks runtime state:

| Field | Description |
|-------|-------------|
| `currentIdentity` | Name of currently active identity |
| `lastSwitch` | ISO 8601 timestamp of last switch |

## Environment Variables

Override settings via environment variables:

| Variable | Overrides |
|----------|-----------|
| `REMOTE_JUGGLER_CONFIG` | Configuration file path |
| `NO_COLOR` | Disable colored output |
| `REMOTE_JUGGLER_VERBOSE` | Enable verbose logging |

## CLI Configuration Flags

Override settings per-invocation (see `src/remote_juggler.chpl:181-187`):

```bash
remote-juggler --configPath=/custom/config.json list
remote-juggler --useKeychain=false switch work
remote-juggler --gpgSign=false validate personal
remote-juggler --verbose status
```

## Configuration Management Commands

```bash
# Show full configuration
remote-juggler config show

# Show specific sections
remote-juggler config show identities
remote-juggler config show settings
remote-juggler config show ssh-hosts
remote-juggler config show rewrites

# Initialize configuration
remote-juggler config init

# Import from SSH config
remote-juggler config import

# Synchronize managed blocks
remote-juggler config sync

# Add/edit/remove identities
remote-juggler config add <name>
remote-juggler config edit <name>
remote-juggler config remove <name>
```

## Managed Configuration Blocks

RemoteJuggler can manage sections of `~/.ssh/config` and `~/.gitconfig` marked with special comments:

```
# BEGIN REMOTE-JUGGLER MANAGED
Host gitlab-work
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
# END REMOTE-JUGGLER MANAGED
```

Run `remote-juggler config sync` to update these blocks from your identity configuration.

## Example: Multi-Account Setup

```json
{
  "version": "2.0.0",
  "identities": {
    "work-gitlab": {
      "provider": "gitlab",
      "host": "gitlab-work",
      "hostname": "gitlab.com",
      "user": "Work User",
      "email": "user@company.com",
      "gpg": {
        "keyId": "WORK_GPG_KEY",
        "signCommits": true
      }
    },
    "personal-gitlab": {
      "provider": "gitlab",
      "host": "gitlab-personal",
      "hostname": "gitlab.com",
      "user": "Personal Name",
      "email": "personal@email.com"
    },
    "github-oss": {
      "provider": "github",
      "host": "github.com",
      "hostname": "github.com",
      "user": "GitHub User",
      "email": "github@email.com",
      "gpg": {
        "keyId": "GITHUB_GPG_KEY",
        "signCommits": true,
        "signTags": true
      }
    }
  },
  "settings": {
    "defaultProvider": "gitlab",
    "autoDetect": true,
    "useKeychain": true,
    "gpgSign": true
  }
}
```
