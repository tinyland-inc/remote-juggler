---
title: "CLI Commands"
description: "Complete command reference including switch, detect, validate, list, token management, GPG configuration, KeePassXC credential authority, YubiKey, and trusted workstation commands."
category: "cli"
llm_priority: 2
keywords:
  - cli
  - commands
  - switch
  - detect
  - validate
  - token
  - keys
  - yubikey
  - trusted-workstation
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

**Implementation:** `src/remote_juggler.chpl`

---

### detect

Detect the appropriate identity for the current repository based on remote URL.

```bash
remote-juggler detect [<path>] [--quiet]
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `path` | Repository path (default: current directory) |
| `--quiet` | Output only the identity name (for scripting) |

**Detection logic:**

1. Parse remote URL from `git remote get-url origin`
2. Extract SSH host alias or hostname
3. Match against configured identities by host field
4. Return matched identity with confidence level

**Implementation:** `src/remote_juggler.chpl`

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

**Implementation:** `src/remote_juggler.chpl`

---

### validate

Test SSH and API connectivity for an identity.

```bash
remote-juggler validate <identity>
remote-juggler test <identity>  # alias
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

**Implementation:** `src/remote_juggler.chpl`

---

### verify

Verify GPG keys are valid and registered with providers.

```bash
remote-juggler verify
```

**Implementation:** `src/remote_juggler.chpl`

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

**Implementation:** `src/remote_juggler.chpl`

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

**Implementation:** `src/remote_juggler.chpl`

---

### config add

Add a new identity interactively.

```bash
remote-juggler config add <name>
```

---

### config edit

Edit an existing identity.

```bash
remote-juggler config edit <name>
```

---

### config remove

Remove an identity from configuration.

```bash
remote-juggler config remove <name>
remote-juggler config rm <name>      # alias
remote-juggler config delete <name>  # alias
```

---

### config import

Import identities from SSH config.

```bash
remote-juggler config import
```

Parses `~/.ssh/config` for git-related hosts (those pointing to known git providers or containing "git" in hostname).

**Implementation:** `src/remote_juggler.chpl`

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

**Implementation:** `src/remote_juggler.chpl`

---

### config init

Initialize a new configuration file.

```bash
remote-juggler config init
```

---

## Token Management

### token set

Store a token in the system keychain.

```bash
remote-juggler token set <identity>
```

Prompts for token input (hidden). Token is stored with service name format:

```
remote-juggler.<provider>.<identity>
```

**Implementation:** `src/remote_juggler.chpl`

---

### token get

Retrieve a stored token (masked output).

```bash
remote-juggler token get <identity>
```

Shows first 4 and last 4 characters of the token.

**Implementation:** `src/remote_juggler.chpl`

---

### token clear

Remove a token from storage.

```bash
remote-juggler token clear <identity>
remote-juggler token delete <identity>  # alias
remote-juggler token rm <identity>      # alias
```

**Implementation:** `src/remote_juggler.chpl`

---

### token verify

Test credential availability for all identities.

```bash
remote-juggler token verify
remote-juggler token test  # alias
```

Checks each identity for:
- Keychain token
- KeePassXC credential store
- Environment variable
- CLI authentication (glab/gh)

**Implementation:** `src/remote_juggler.chpl`

---

### token check-expiry

Check token expiration status.

```bash
remote-juggler token check-expiry
remote-juggler token expiry  # alias
remote-juggler token check   # alias
```

Reports tokens that are expired or approaching expiry.

**Implementation:** `src/remote_juggler/TokenHealth.chpl`

---

### token renew

Initiate token renewal workflow.

```bash
remote-juggler token renew <identity>
remote-juggler token refresh <identity>  # alias
```

**Implementation:** `src/remote_juggler/TokenHealth.chpl`

---

## GPG Signing

### gpg status

Show GPG configuration for all identities.

```bash
remote-juggler gpg status
```

Lists available GPG keys and per-identity configuration.

**Implementation:** `src/remote_juggler.chpl`

---

### gpg configure

Configure GPG signing for an identity.

```bash
remote-juggler gpg configure <identity>
remote-juggler gpg config <identity>  # alias
```

Attempts to find GPG key matching the identity's email address.

**Implementation:** `src/remote_juggler.chpl`

---

### gpg verify

Verify GPG keys are registered with providers.

```bash
remote-juggler gpg verify
remote-juggler gpg check  # alias
```

Checks provider settings pages for GPG key registration.

**Implementation:** `src/remote_juggler.chpl`

---

## KeePassXC Credential Authority

The `keys` command (alias: `kdbx`) manages the KeePassXC-backed credential store at `~/.remotejuggler/keys.kdbx`.

### keys init

Initialize the credential store.

```bash
remote-juggler keys init
```

Creates a new `.kdbx` database. Master password is backed by TPM/Secure Enclave when available.

**Implementation:** `src/remote_juggler/KeePassXC.chpl`

---

### keys status

Show credential store status.

```bash
remote-juggler keys status
```

Reports: database path, lock state, entry count, HSM binding status.

---

### keys search

Fuzzy search credentials.

```bash
remote-juggler keys search <query> [--field=<field>] [--group=<group>] [--json]
remote-juggler keys find <query>  # alias
```

**Options:**

| Option | Description |
|--------|-------------|
| `--field` | Search specific field: `username`, `notes`, `url` |
| `--group` | Filter by KeePassXC group |
| `--json` | Output as JSON |

Uses Levenshtein distance + word boundary + substring fuzzy matching.

---

### keys resolve

Combined search + retrieve in one call.

```bash
remote-juggler keys resolve <query> [--json]
```

Searches for a credential and returns its value if a single match is found.

---

### keys get

Retrieve a specific credential by title.

```bash
remote-juggler keys get <title> [--json]
```

---

### keys store

Store a new credential.

```bash
remote-juggler keys store <title> [--username=<user>] [--url=<url>] [--group=<group>]
remote-juggler keys set <title>  # alias
remote-juggler keys add <title>  # alias
```

Prompts for the secret value.

---

### keys delete

Delete a credential.

```bash
remote-juggler keys delete <title>
remote-juggler keys rm <title>  # alias
```

---

### keys list

List all stored credentials.

```bash
remote-juggler keys list [--group=<group>] [--json]
remote-juggler keys ls  # alias
```

---

### keys ingest

Ingest credentials from environment variables.

```bash
remote-juggler keys ingest [--pattern=<pattern>]
remote-juggler keys import  # alias
```

Detects common patterns: `*_TOKEN`, `*_API_KEY`, `*_SECRET`, etc.

---

### keys crawl

Crawl `.env` files for credentials.

```bash
remote-juggler keys crawl [<path>]
```

Recursively discovers and ingests credentials from `.env` files. Tracks additions, updates, and deletions.

---

### keys discover

Auto-discover credentials from multiple sources.

```bash
remote-juggler keys discover
```

Scans: environment variables, SSH key metadata, `.env` files, and provider CLI tokens.

---

### keys export

Export credentials as environment variables.

```bash
remote-juggler keys export [--group=<group>] [--format=<format>]
remote-juggler keys dump-env  # alias
```

**Formats:** `env` (default), `json`, `shell`

---

## PIN Management

The `pin` command manages HSM PINs for hardware-backed credential unlock.

### pin store

Store a PIN for HSM operations.

```bash
remote-juggler pin store
```

---

### pin clear

Clear stored PIN.

```bash
remote-juggler pin clear
remote-juggler pin delete  # alias
remote-juggler pin rm      # alias
```

---

### pin status

Check PIN availability.

```bash
remote-juggler pin status
remote-juggler pin check  # alias
```

---

## YubiKey Management

The `yubikey` command (alias: `yk`) manages YubiKey hardware keys.

### yubikey info

Show YubiKey information and status.

```bash
remote-juggler yubikey info
remote-juggler yubikey status  # alias
```

---

### yubikey set-pin-policy

Configure PIN caching policy.

```bash
remote-juggler yubikey set-pin-policy <policy>
remote-juggler yubikey pin-policy <policy>  # alias
```

---

### yubikey set-touch

Configure touch requirement.

```bash
remote-juggler yubikey set-touch <policy>
remote-juggler yubikey touch <policy>  # alias
```

---

### yubikey configure-trusted

Configure YubiKey for trusted workstation mode.

```bash
remote-juggler yubikey configure-trusted
remote-juggler yubikey trusted  # alias
```

---

### yubikey diagnostics

Run YubiKey diagnostic checks.

```bash
remote-juggler yubikey diagnostics
remote-juggler yubikey diag   # alias
remote-juggler yubikey check  # alias
```

---

## Trusted Workstation

The `trusted-workstation` command (alias: `tws`) manages TPM/Secure Enclave-based auto-unlock.

### trusted-workstation enable

Enable trusted workstation mode.

```bash
remote-juggler trusted-workstation enable
```

Binds the credential store to TPM PCR 7 (Secure Boot state) and YubiKey presence.

---

### trusted-workstation disable

Disable trusted workstation mode.

```bash
remote-juggler trusted-workstation disable
```

---

### trusted-workstation status

Show trusted workstation status.

```bash
remote-juggler trusted-workstation status
```

---

### trusted-workstation verify

Verify trusted workstation configuration.

```bash
remote-juggler trusted-workstation verify
```

---

## Security Mode

### security-mode

Set the security mode for credential operations.

```bash
remote-juggler security-mode <mode>
```

Available modes depend on hardware capabilities (TPM, YubiKey, Secure Enclave).

---

## Setup

### setup

Run the interactive setup wizard.

```bash
remote-juggler setup [--import-ssh] [--import-gpg]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--import-ssh` | Import SSH hosts only |
| `--import-gpg` | Import GPG keys only |

Without options, runs the full interactive setup wizard.

**Implementation:** `src/remote_juggler/Setup.chpl`

---

## Unseal PIN

### unseal-pin

Unseal the HSM PIN using hardware attestation.

```bash
remote-juggler unseal-pin
```

Uses TPM/Secure Enclave to unseal the credential store master password.

---

## Debug Commands

### debug ssh-config

Display parsed SSH configuration.

```bash
remote-juggler debug ssh-config
remote-juggler debug ssh  # alias
```

Shows all Host entries from `~/.ssh/config` with:
- Hostname
- User
- IdentityFile
- Port (if non-default)
- ProxyJump (if configured)

**Implementation:** `src/remote_juggler.chpl`

---

### debug git-config

Display parsed gitconfig URL rewrites.

```bash
remote-juggler debug git-config
remote-juggler debug gitconfig  # alias
remote-juggler debug git        # alias
```

Shows `insteadOf` URL rewrite rules and user configuration.

**Implementation:** `src/remote_juggler.chpl`

---

### debug keychain

Test Keychain access.

```bash
remote-juggler debug keychain
```

Performs store/retrieve/delete test cycle to verify Keychain integration.

**Implementation:** `src/remote_juggler.chpl`

---

### debug hsm

Debug HSM/TPM/Secure Enclave connectivity.

```bash
remote-juggler debug hsm
remote-juggler debug tpm             # alias
remote-juggler debug secure-enclave  # alias
```

Reports hardware security module status, PCR values, and attestation state.

**Implementation:** `src/remote_juggler.chpl`

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Configuration error |
| 3 | Validation failure |
