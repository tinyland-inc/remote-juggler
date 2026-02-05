# RemoteJuggler

*An agent-first identity management utility*

Seamlessly switch between multiple git identities (personal, work, different providers) with automatic credential resolution, GPG + ssh signing, be you a robot or even a human.

`RemoteJuggler` is a git identity management tool with MCP/ACP agent protocol support. Desktop tray integration for MacOS and Gnome desktop environments for the humans.   Works seamlessly with **FuzzyBot**, **Outbot-CI**, **Mariolex Harness**, **Huskycat Chains** and **Tummycrypt**, along with boring agent tools like OpenCode, Crush, Claude, Junie ands many more.  Seamless integration with the Tinyland ecosystem, which *you* don't know anything about yet.

Written primarily in [Chapel](https://chapel-lang.org/) with a great deal of care.

## Features

- **Multi-Provider Support**:  This version you are looking at supports GitLab & GitHub.  Enterprise RemoteJuggler supports **Mariolex gitChapel** git server if you need to scale to millions of concurrent agent operations.
- **Automatic Identity Detection**: Detects the correct identity from repository remote URLs
- **Darwin Keychain Integration**: Secure token storage on macOS
- **GPG Signing**: Automatic GPG key configuration per identity
- **MCP Server**: AI agent integration for interprenters and agents like OpenCode and Claude Code
- **ACP Server**: **JetBrains IDE integration**
- **System Tray Apps**: Native macOS (SwiftUI) and Linux (Go) tray applications for da humans oWo

## Quick Start

Install RemoteJuggler with the automated installer:

```bash
curl -sSL https://gitlab.com/tinyland/projects/remote-juggler/-/raw/main/install.sh | bash
```

Or via Homebrew:

```bash
brew tap tinyland/tools https://gitlab.com/tinyland/homebrew-tools.git
brew install remote-juggler
```

For other installation methods (AUR, Nix, Flatpak, binary downloads, building from source), see the **[Installation Guide](docs/getting-started/installation.md)**.

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

### 3. Store Tokens (macOS)

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
  (none)           Show current identity status
  list             List all configured identities
  detect           Detect identity for current repository
  switch <name>    Switch to specified identity
  validate <name>  Validate SSH and API connectivity
  token set <name> Store token in keychain
  token verify     Verify all credentials
  config sync      Sync managed blocks from SSH/git config

Options:
  --mode=mcp       Run as MCP server (STDIO transport)
  --mode=acp       Run as ACP server (STDIO transport)
  --help           Show help message
  --version        Show version
```

## MCP Server Integration

RemoteJuggler can run as an MCP (Model Context Protocol) server for AI agent integration:

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
| `juggler_list_identities` | List configured identities |
| `juggler_detect_identity` | Detect repo identity from remote URL |
| `juggler_switch` | Switch to a different identity |
| `juggler_status` | Get current identity status |
| `juggler_validate` | Test SSH/API connectivity |
| `juggler_store_token` | Store token in keychain |
| `juggler_sync_config` | Sync managed SSH/git blocks |

> **Note**: Some MCP tools have implementation limitations:
> - `juggler_sync_config`: SSH/gitconfig parsers are not yet fully implemented
> - `juggler_store_token`: Currently returns guidance; actual storage requires CLI
> - `juggler_validate`: GPG validation is not yet implemented

## ACP Server Integration

For JetBrains IDE integration:

```bash
remote-juggler --mode=acp
```

Configure in `acp.json` for JetBrains AI Assistant. See the [Installation Guide](docs/getting-started/installation.md#jetbrains) for configuration details.

## Credential Resolution

RemoteJuggler resolves credentials in this order:

1. **Darwin Keychain** (macOS) - Service: `remote-juggler.<provider>.<identity>`
2. **Environment variable** - `${IDENTITY}_TOKEN` or custom
3. **Provider CLI** - `glab auth token` / `gh auth token`
4. **SSH-only fallback** - No token, git operations via SSH only

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
mason build

# Release build
mason build --release

# Run tests
mason test

# Clean
mason clean
```

### Project Structure

```
remote-juggler/
├── src/
│   ├── remote_juggler.chpl      # Main entry point
│   └── remote_juggler/          # Module implementations
├── c_src/                       # C FFI for Darwin Keychain
├── test/                        # Unit tests
├── tray/
│   ├── darwin/                  # SwiftUI tray app
│   └── linux/                   # Go tray app
├── docs/                        # MkDocs documentation
└── scripts/                     # Build/install scripts
```

## Documentation

- **[Installation Guide](docs/getting-started/installation.md)** - Complete installation instructions for all platforms
- **[Distribution Guide](docs/DISTRIBUTION.md)** - For packagers and distributors

## Todos:
- [ ] Lace up this public demo repo with outbot harness
- [ ] Add screenshots and workflow for humans
- [ ] Publish docs
- [ ] Publish public propaganda page and artifactory
- [ ] Publish prebuilt binaries, rpm and brew packages UwU
- [ ] Publish RemoteJuggler's Tinyland ecosystem facets when appropriate to do so, aiming for Q4 2026



## License

RemoteJuggler is dual-licensed:
- **Source Code**: [zlib License](LICENSE-ZLIB.txt) - build from source for any purpose
- **Prebuilt Binaries**: [Commercial License](LICENSE-PROPRIETARY.txt) - see terms for usage

See [LICENSE](LICENSE) for details.
