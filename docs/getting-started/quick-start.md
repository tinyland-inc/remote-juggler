---
title: "Quick Start"
description: "Get started with RemoteJuggler: import identities from SSH config, switch between them, store credentials, and integrate with AI assistants."
category: "operations"
llm_priority: 2
keywords:
  - quickstart
  - tutorial
  - setup
  - import
  - switch
---

# Quick Start

Configure your first identity in 5 minutes.

## Prerequisites

Ensure you have SSH keys configured in `~/.ssh/config` for each git identity. Example:

```
Host gitlab-work
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work

Host gitlab-personal
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal
```

## Step 1: Import Identities

Import identities from your SSH config:

```bash
remote-juggler config import
```

Output:

```
Importing from SSH config...

[OK] Imported 2 identities

  - gitlab-work
  - gitlab-personal
```

The import reads `~/.ssh/config` and creates identities for git-related hosts (those pointing to gitlab.com, github.com, bitbucket.org, or containing "git" in the hostname).

## Step 2: List Identities

View all configured identities:

```bash
remote-juggler list
```

Output:

```
Identity       Provider  SSH Host         User           Email           GPG
--------------------------------------------------------------------------------
*gitlab-work   GitLab    gitlab-work      work-user      work@company.com  No
 gitlab-personal GitLab  gitlab-personal  personal-user  me@email.com      No
```

The `*` indicates the currently active identity.

## Step 3: Switch Identity

Switch to a different identity:

```bash
remote-juggler switch gitlab-personal
```

Output:

```
[OK] Switched to gitlab-personal

  Provider: GitLab
  User:     personal-user <me@email.com>
  SSH Host: gitlab-personal
  Auth:     SSH-only mode
```

This updates:

- `~/.gitconfig` user.name and user.email
- Local repository remote URLs (if in a git repo)
- State tracking for identity detection

## Step 4: Store Credentials (macOS)

For API operations (push, pull with HTTPS, etc.), store tokens in Keychain:

```bash
remote-juggler token set gitlab-personal
```

Enter your GitLab/GitHub personal access token when prompted. The token is stored securely in macOS Keychain with service name `remote-juggler.gitlab.gitlab-personal`.

## Step 5: Validate Connectivity

Test SSH and API connectivity:

```bash
remote-juggler validate gitlab-personal
```

Output:

```
Validating: gitlab-personal (GitLab)

  SSH Connection... OK
  Credentials...    OK
```

## Using in a Repository

When you enter a git repository, RemoteJuggler can detect the appropriate identity:

```bash
cd ~/projects/work-project
remote-juggler detect
```

Output:

```
Detected Identity: gitlab-work
  Confidence: high
  Reasons:
    - Remote URL matches SSH host gitlab-work
```

## AI Assistant Integration

### Claude Code

After installation, use the `/juggle` command:

```
/juggle gitlab-work
```

### MCP Server Mode

Start RemoteJuggler as an MCP server for other AI assistants:

```bash
remote-juggler --mode=mcp
```

Or add to `.mcp.json` in your project:

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

## Next Steps

- [Configuration](configuration.md) - Customize settings
- [Identity Switching](../operations/identity-switching.md) - Advanced switching workflows
- [GPG Signing](../operations/gpg-signing.md) - Configure commit signing
