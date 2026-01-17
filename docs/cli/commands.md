---
title: "CLI Commands"
description: "Complete command reference including switch, detect, validate, list, token management, and GPG configuration commands."
category: "cli"
llm_priority: 2
keywords:
  - cli
  - commands
  - switch
  - detect
  - validate
  - token
---

# CLI Commands

Detailed reference for all RemoteJuggler commands.

## Identity Management

### list

List all configured identities.

```bash
remote-juggler list [--provider=<provider>]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--provider` | Filter by provider: `gitlab`, `github`, `bitbucket`, `all` |

**Output columns:**

| Column | Description |
|--------|-------------|
| Identity | Identity name (with `*` for current) |
| Provider | GitLab, GitHub, Bitbucket, or Custom |
| SSH Host | SSH config host alias |
| User | Git user.name |
| Email | Git user.email |
| GPG | Whether GPG signing is configured |

**Implementation:** `src/remote_juggler.chpl:413-427`

---

### detect

Detect the appropriate identity for the current repository based on remote URL.

```bash
remote-juggler detect [<path>]
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `path` | Repository path (default: current directory) |

**Detection logic:**

1. Parse remote URL from `git remote get-url origin`
2. Extract SSH host alias or hostname
3. Match against configured identities by host field
4. Return matched identity with confidence level

**Implementation:** `src/remote_juggler.chpl:429-461`

---

### switch

Switch to a different git identity.

```bash
remote-juggler switch <identity>
remote-juggler to <identity>  # alias
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `identity` | Identity name to switch to |

**Actions performed:**

1. Load identity configuration
2. Update `git config user.name` and `user.email`
3. Update remote URL if using SSH alias
4. Configure GPG signing key (if configured)
5. Authenticate with provider CLI (glab/gh) if token available

**Implementation:** `src/remote_juggler.chpl:464-518`

---

### validate

Test SSH and API connectivity for an identity.

```bash
remote-juggler validate <identity>
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `identity` | Identity name to validate |

**Tests performed:**

1. SSH connection to host alias
2. Credential availability (Keychain/environment/CLI)
3. GPG key existence (if configured)
4. GPG registration with provider (if `--gpgSign`)

**Implementation:** `src/remote_juggler.chpl:520-597`

---

### status

Show current identity status and repository context.

```bash
remote-juggler status
```

**Output includes:**

- Current identity name and provider
- User name and email
- SSH host alias
- GPG key status
- Authentication mode
- Repository information (if in a git repo)
- Last switch timestamp

**Implementation:** `src/remote_juggler.chpl:599-622`

---

## Configuration

### config show

Display configuration.

```bash
remote-juggler config show [<section>]
```

**Sections:**

| Section | Description |
|---------|-------------|
| `identities` | List of configured identities |
| `settings` | Global settings |
| `ssh-hosts` | Managed SSH hosts |
| `rewrites` | Git URL rewrites |

**Implementation:** `src/remote_juggler.chpl:650-715`

---

### config import

Import identities from SSH config.

```bash
remote-juggler config import
```

Parses `~/.ssh/config` for git-related hosts (those pointing to known git providers or containing "git" in hostname).

**Implementation:** `src/remote_juggler.chpl:799-818`

---

### config sync

Synchronize managed configuration blocks.

```bash
remote-juggler config sync
```

Updates managed sections in `~/.ssh/config` and `~/.gitconfig` marked with:

```
# BEGIN REMOTE-JUGGLER MANAGED
...
# END REMOTE-JUGGLER MANAGED
```

**Implementation:** `src/remote_juggler.chpl:820-839`

---

## Token Management

### token set

Store a token in macOS Keychain.

```bash
remote-juggler token set <identity>
```

Prompts for token input (hidden). Token is stored with service name format:

```
remote-juggler.<provider>.<identity>
```

**Implementation:** `src/remote_juggler.chpl:876-923`

---

### token get

Retrieve a stored token (masked output).

```bash
remote-juggler token get <identity>
```

Shows first 4 and last 4 characters of the token.

**Implementation:** `src/remote_juggler.chpl:925-957`

---

### token clear

Remove a token from Keychain.

```bash
remote-juggler token clear <identity>
```

**Implementation:** `src/remote_juggler.chpl:959-986`

---

### token verify

Test credential availability for all identities.

```bash
remote-juggler token verify
```

Checks each identity for:
- Keychain token
- Environment variable
- CLI authentication (glab/gh)

**Implementation:** `src/remote_juggler.chpl:988-1006`

---

## GPG Signing

### gpg status

Show GPG configuration for all identities.

```bash
remote-juggler gpg status
```

Lists available GPG keys and per-identity configuration.

**Implementation:** `src/remote_juggler.chpl:1030-1072`

---

### gpg configure

Configure GPG signing for an identity.

```bash
remote-juggler gpg configure <identity>
```

Attempts to find GPG key matching the identity's email address.

**Implementation:** `src/remote_juggler.chpl:1074-1108`

---

### gpg verify

Verify GPG keys are registered with providers.

```bash
remote-juggler gpg verify
```

Checks provider settings pages for GPG key registration.

**Implementation:** `src/remote_juggler.chpl:1110-1136`

---

## Debug Commands

### debug ssh-config

Display parsed SSH configuration.

```bash
remote-juggler debug ssh-config
```

Shows all Host entries from `~/.ssh/config` with:
- Hostname
- User
- IdentityFile
- Port (if non-default)
- ProxyJump (if configured)

**Implementation:** `src/remote_juggler.chpl:1159-1184`

---

### debug git-config

Display parsed gitconfig URL rewrites.

```bash
remote-juggler debug git-config
```

Shows `insteadOf` URL rewrite rules and user configuration.

**Implementation:** `src/remote_juggler.chpl:1186-1212`

---

### debug keychain

Test Keychain access.

```bash
remote-juggler debug keychain
```

Performs store/retrieve/delete test cycle to verify Keychain integration.

**Implementation:** `src/remote_juggler.chpl:1214-1258`

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Configuration error |
| 3 | Validation failure |
