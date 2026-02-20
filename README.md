# RemoteJuggler

[![npm](https://img.shields.io/npm/v/@tummycrypt/remote-juggler?color=CB3837)](https://www.npmjs.com/package/@tummycrypt/remote-juggler)
[![GitHub release](https://img.shields.io/github/v/release/Jesssullivan/RemoteJuggler)](https://github.com/Jesssullivan/RemoteJuggler/releases/latest)
[![CI](https://github.com/Jesssullivan/RemoteJuggler/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Jesssullivan/RemoteJuggler/actions/workflows/ci.yml)
[![Docker](https://img.shields.io/badge/ghcr.io-remote--juggler-blue?logo=docker)](https://github.com/Jesssullivan/RemoteJuggler/pkgs/container/remote-juggler)
[![License: Zlib](https://img.shields.io/badge/license-Zlib-blue)](LICENSE)

*An agent-first identity management utility*

Seamlessly switch between multiple git identities (personal, work, different providers) with automatic credential resolution, GPG + ssh signing, be you a robot or even a human.

`RemoteJuggler` is a git identity management tool with MCP/ACP agent protocol support. Desktop tray integration for MacOS and Gnome desktop environments for the humans.   Works seamlessly with **FuzzyBot**, **Outbot-CI**, **Mariolex Harness**, **Huskycat Chains** and **Tummycrypt**, along with boring agent tools like OpenCode, Crush, Claude, Junie ands many more.  Seamless integration with the Tinyland ecosystem, which *you* don't know anything about yet.

Written primarily in [Chapel](https://chapel-lang.org/) with a great deal of care.

## Features

- **Multi-Provider Support**:  This version you are looking at supports GitLab & GitHub.  Enterprise RemoteJuggler supports **Mariolex gitChapel** git server if you need to scale to millions of concurrent agent operations.
- **Automatic Identity Detection**: Detects the correct identity from repository remote URLs
- **KeePassXC Credential Authority**: Secure credential storage and auto-discovery with TPM/YubiKey hardware-backed unlock
- **Darwin Keychain Integration**: Secure token storage on macOS
- **GPG Signing**: Automatic GPG key configuration per identity
- **YubiKey / FIDO2**: Hardware key support with PIN management and touch policies
- **Trusted Workstation Mode**: TPM/Secure Enclave-based auto-unlock for headless environments
- **MCP Server**: 32 tools for AI agent integration (Claude Code, Cursor, VS Code, Windsurf)
- **ACP Server**: **JetBrains IDE integration**
- **System Tray Apps**: Native macOS (SwiftUI) and Linux (Go) tray applications for da humans oWo
- **GTK4 GUI**: Libadwaita desktop app for Linux

## Quick Start

Install RemoteJuggler with the automated installer:

```bash
curl -sSL https://raw.githubusercontent.com/Jesssullivan/RemoteJuggler/main/install.sh | bash
```

Or via npm (all platforms):

```bash
npx @tummycrypt/remote-juggler@latest --version
```

Or via Homebrew:

```bash
brew tap tinyland/tools https://gitlab.com/tinyland/homebrew-tools.git
brew install remote-juggler
```

Or via Nix:

```bash
nix profile install github:Jesssullivan/RemoteJuggler
```

For other installation methods (AUR, Flatpak, .deb, .rpm, binary downloads, building from source), see the **[Installation Guide](docs/getting-started/installation.md)**.

## Binary Downloads

Pre-built binaries are attached to each [GitHub Release](https://github.com/Jesssullivan/RemoteJuggler/releases/latest):

| Platform | CLI | GTK GUI | Tray |
|----------|-----|---------|------|
| Linux x86_64 | `remote-juggler-linux-amd64` | `remote-juggler-gui-linux-amd64` | `remote-juggler-tray-linux-amd64` |
| Linux ARM64 | `remote-juggler-linux-arm64` | `remote-juggler-gui-linux-arm64` | `remote-juggler-tray-linux-arm64` |
| macOS ARM64 | `remote-juggler-darwin-arm64` | -- | `remote-juggler-tray-darwin-arm64` |
| macOS x86_64 | `remote-juggler-darwin-amd64` | -- | -- |
| AppImage | -- | `.AppImage` | -- |
| .deb (amd64) | `.deb` | -- | -- |
| .rpm (x86_64) | `.rpm` | -- | -- |
| Docker | `ghcr.io/jesssullivan/remote-juggler` | -- | -- |

Verify your download:

```bash
sha256sum -c SHA256SUMS.txt
# Or check an individual file
sha256sum -c remote-juggler-linux-amd64.sha256
```

> **Note:** macOS binaries from GitHub are unsigned. For signed/notarized macOS builds, see [GitLab Releases](https://gitlab.com/tinyland/projects/remote-juggler/-/releases).

## Configuration

### 1. Configure SSH Hosts

Add identity-specific SSH hosts to `~/.ssh/config`:

```ssh-config
Host gitlab-personal
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal

Host gitlab-work
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work

Host github-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
```

### 2. Create Configuration

The tool auto-generates `~/.config/remote-juggler/config.json` on first run, or you can create it:

```json
{
  "identities": {
    "personal": {
      "provider": "gitlab",
      "host": "gitlab-personal",
      "hostname": "gitlab.com",
      "user": "your-username",
      "email": "you@personal.com",
      "sshKeyPath": "~/.ssh/id_ed25519_personal",
      "gpg": {
        "keyId": "ABCD1234",
        "signCommits": true
      }
    },
    "work": {
      "provider": "gitlab",
      "host": "gitlab-work",
      "hostname": "gitlab.com",
      "user": "work-username",
      "email": "you@company.com",
      "sshKeyPath": "~/.ssh/id_ed25519_work"
    },
    "github": {
      "provider": "github",
      "host": "github-personal",
      "hostname": "github.com",
      "user": "github-user",
      "email": "you@personal.com",
      "sshKeyPath": "~/.ssh/id_ed25519_github"
    }
  }
}
```

### 3. Store Tokens

```bash
# Store GitLab token in Keychain
remote-juggler token set personal
# Prompts for token

# Store GitHub token
remote-juggler token set github
```

### 4. Switch Identities

```bash
# Show current status
remote-juggler

# List all identities
remote-juggler list

# Switch to work identity
remote-juggler switch work

# Detect identity for current repo
remote-juggler detect

# Validate connectivity
remote-juggler validate personal
```

## CLI Usage

```bash
remote-juggler [command] [options]

Commands:
  (none)                    Show current identity status
  list                      List all configured identities
  detect                    Detect identity for current repository
  switch <name>             Switch to specified identity
  validate <name>           Validate SSH and API connectivity
  verify                    Verify GPG keys
  status                    Show current identity status

  config show|add|edit|remove|import|sync|init
                            Configuration management

  token set|get|clear|verify|check-expiry|renew
                            Token/credential management

  gpg status|configure|verify
                            GPG signing configuration

  keys init|status|search|resolve|get|store|delete|list|ingest|crawl|discover|export
                            KeePassXC credential authority

  pin store|clear|status    HSM PIN management
  yubikey info|set-pin-policy|set-touch|configure-trusted|diagnostics
                            YubiKey management
  trusted-workstation enable|disable|status|verify
                            Trusted workstation mode
  security-mode <mode>      Set security mode
  setup                     Interactive setup wizard
  unseal-pin                Unseal HSM PIN

  debug ssh-config|git-config|keychain|hsm
                            Debug utilities

Options:
  --mode=mcp       Run as MCP server (STDIO transport)
  --mode=acp       Run as ACP server (STDIO transport)
  --help           Show help message
  --version        Show version
```

## MCP Server Integration

RemoteJuggler implements an MCP (Model Context Protocol) server with 32 tools for AI agent integration:

```bash
remote-juggler --mode=mcp
```

### Claude Code Integration

Add to your `.mcp.json`:

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

### Available MCP Tools

| Tool | Description |
|------|-------------|
| **Identity Management** | |
| `juggler_list_identities` | List configured identities |
| `juggler_detect_identity` | Detect repo identity from remote URL |
| `juggler_switch` | Switch to a different identity |
| `juggler_status` | Get current identity status |
| `juggler_validate` | Test SSH/API connectivity |
| `juggler_store_token` | Store token in keychain |
| `juggler_sync_config` | Sync managed SSH/git blocks |
| **Security & GPG** | |
| `juggler_gpg_status` | GPG key status |
| `juggler_pin_store` | Store HSM PIN |
| `juggler_pin_clear` | Clear HSM PIN |
| `juggler_pin_status` | Check PIN status |
| `juggler_security_mode` | Set security mode |
| `juggler_setup` | Run setup wizard |
| `juggler_tws_status` | Trusted workstation status |
| `juggler_tws_enable` | Enable trusted workstation |
| **Token Management** | |
| `juggler_token_verify` | Verify tokens |
| `juggler_token_get` | Retrieve stored token |
| `juggler_token_clear` | Clear stored token |
| **Configuration & Debug** | |
| `juggler_config_show` | Show configuration |
| `juggler_debug_ssh` | Debug SSH config |
| **Credential Authority (KeePassXC)** | |
| `juggler_keys_init` | Initialize credential store |
| `juggler_keys_status` | Credential store status |
| `juggler_keys_search` | Fuzzy search credentials |
| `juggler_keys_resolve` | Search + retrieve in one call |
| `juggler_keys_get` | Get specific credential |
| `juggler_keys_store` | Store credential |
| `juggler_keys_delete` | Delete credential |
| `juggler_keys_list` | List all credentials |
| `juggler_keys_ingest_env` | Ingest from environment |
| `juggler_keys_crawl_env` | Crawl .env files |
| `juggler_keys_discover` | Auto-discover credentials |
| `juggler_keys_export` | Export as env vars |

## ACP Server Integration

For JetBrains IDE integration:

```bash
remote-juggler --mode=acp
```

Configure in `acp.json` for JetBrains AI Assistant. See the [Installation Guide](docs/getting-started/installation.md#jetbrains) for configuration details.

## KeePassXC Credential Authority

RemoteJuggler includes a built-in credential authority backed by KeePassXC (`.kdbx` format) with hardware-backed security:

```bash
# Initialize credential store
remote-juggler keys init

# Auto-discover credentials from environment
remote-juggler keys discover

# Search credentials with fuzzy matching
remote-juggler keys search "gitlab token"

# Crawl .env files
remote-juggler keys crawl

# Export as environment variables
remote-juggler keys export
```

**Security model**: TPM/Secure Enclave + YubiKey presence = auto-unlock with 30-second session cache.

## Credential Resolution

RemoteJuggler resolves credentials in this order:

1. **KeePassXC Store** - Hardware-backed credential authority (`~/.remotejuggler/keys.kdbx`)
2. **Darwin Keychain** (macOS) - Service: `remote-juggler.<provider>.<identity>`
3. **Environment variable** - `${IDENTITY}_TOKEN` or custom
4. **Provider CLI** - `glab auth token` / `gh auth token`
5. **SSH-only fallback** - No token, git operations via SSH only

## System Tray Application (Experimental)

> **Note**: The tray applications are experimental and provide basic functionality only.

### macOS

The macOS tray app provides a menu bar interface for quick identity switching:

```bash
# Install via DMG or build from source
cd tray/darwin
swift build -c release
```

### Linux

The Linux tray app uses GTK/AppIndicator:

```bash
cd tray/linux
go build -o remote-juggler-tray
```

## Development

### Build Commands

```bash
# Debug build
just build

# Release build
just release

# Run tests
just test

# Build GTK GUI (Linux)
just gui-release
```

### Project Structure

```
remote-juggler/
├── src/
│   ├── remote_juggler.chpl      # Main entry point
│   └── remote_juggler/          # 20 Chapel modules
│       ├── Core.chpl            # Version, helpers, formatting
│       ├── Config.chpl          # Configuration management
│       ├── GlobalConfig.chpl    # Schema versioning
│       ├── State.chpl           # State persistence
│       ├── Identity.chpl        # Identity switching
│       ├── Remote.chpl          # Remote URL management
│       ├── Keychain.chpl        # macOS Keychain integration
│       ├── GPG.chpl             # GPG signing
│       ├── ProviderCLI.chpl     # Provider CLI wrappers
│       ├── Protocol.chpl        # JSON-RPC protocol
│       ├── MCP.chpl             # MCP server
│       ├── ACP.chpl             # ACP server
│       ├── Tools.chpl           # MCP/ACP tool definitions
│       ├── HSM.chpl             # TPM/Secure Enclave
│       ├── YubiKey.chpl         # YubiKey management
│       ├── TrustedWorkstation.chpl # Auto-unlock mode
│       ├── GPGAgent.chpl        # GPG agent integration
│       ├── TokenHealth.chpl     # Token expiry detection
│       ├── Setup.chpl           # Interactive setup wizard
│       └── KeePassXC.chpl       # Credential authority
├── gtk-gui/                     # Rust/GTK4/Libadwaita GUI
├── tray/
│   ├── darwin/                  # SwiftUI tray app
│   └── linux/                   # Go tray app
├── pinentry/                    # HSM pinentry helper
├── docs/                        # MkDocs documentation
├── packaging/                   # .deb/.rpm/AUR/Flatpak packaging
└── scripts/                     # Build/install scripts
```

## Documentation

- **[Installation Guide](docs/getting-started/installation.md)** - Complete installation instructions for all platforms
- **[CLI Commands](docs/cli/commands.md)** - Full command reference
- **[MCP Server](docs/integrations/mcp.md)** - MCP integration guide
- **[Distribution Guide](docs/DISTRIBUTION.md)** - For packagers and distributors

## License

RemoteJuggler is licensed under the [zlib License](LICENSE).
