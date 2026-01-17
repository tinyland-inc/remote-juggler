# RemoteJuggler

A backend-agnostic git identity management tool with MCP/ACP agent protocol support. Seamlessly switch between multiple git identities (personal, work, different providers) with automatic credential resolution, GPG signing, and IDE integration.

Written in [Chapel](https://chapel-lang.org/) for high performance and cross-platform support.

## Features

- **Multi-Provider Support**: GitLab, GitHub, Bitbucket, and custom git servers
- **Automatic Identity Detection**: Detects the correct identity from repository remote URLs
- **Darwin Keychain Integration**: Secure token storage on macOS
- **GPG Signing**: Automatic GPG key configuration per identity
- **MCP Server**: AI agent integration for Claude Code
- **ACP Server**: JetBrains IDE integration
- **System Tray Apps**: Native macOS (SwiftUI) and Linux (Go) tray applications

## Installation

### Quick Install (Recommended)

```bash
curl -fsSL https://gitlab.com/tinyland/projects/remote-juggler/-/raw/main/install.sh | bash
```

### macOS (DMG)

Download the latest notarized DMG from [Releases](https://gitlab.com/tinyland/projects/remote-juggler/-/releases) and drag to Applications.

### Linux Packages

```bash
# Debian/Ubuntu
sudo dpkg -i remote-juggler_*.deb

# RHEL/Fedora
sudo rpm -i remote-juggler-*.rpm

# Arch Linux
sudo pacman -U remote-juggler-*.pkg.tar.zst
```

### Build from Source

Requires [Chapel 2.8+](https://chapel-lang.org/download.html).

```bash
git clone https://gitlab.com/tinyland/projects/remote-juggler.git
cd remote-juggler
mason build --release
./target/release/remote_juggler --help
```

## Quick Start

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
      "user": "your-username",
      "email": "you@personal.com",
      "sshKey": "~/.ssh/id_ed25519_personal",
      "gpgKey": "ABCD1234"
    },
    "work": {
      "provider": "gitlab",
      "host": "gitlab-work",
      "user": "work-username",
      "email": "you@company.com",
      "sshKey": "~/.ssh/id_ed25519_work"
    },
    "github": {
      "provider": "github",
      "host": "github-personal",
      "user": "github-user",
      "email": "you@personal.com",
      "sshKey": "~/.ssh/id_ed25519_github"
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

## ACP Server Integration

For JetBrains IDE integration:

```bash
remote-juggler --mode=acp
```

Configure in `acp.json` for JetBrains AI Assistant.

## Credential Resolution

RemoteJuggler resolves credentials in this order:

1. **Darwin Keychain** (macOS) - Service: `remote-juggler.<provider>.<identity>`
2. **Environment variable** - `${IDENTITY}_TOKEN` or custom
3. **Provider CLI** - `glab auth token` / `gh auth token`
4. **SSH-only fallback** - No token, git operations via SSH only

## System Tray Application

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

## Documentation

Full documentation available at: https://tinyland.gitlab.io/projects/remote-juggler

- [Getting Started](https://tinyland.gitlab.io/projects/remote-juggler/getting-started/)
- [Configuration](https://tinyland.gitlab.io/projects/remote-juggler/getting-started/configuration/)
- [CLI Commands](https://tinyland.gitlab.io/projects/remote-juggler/cli/commands/)
- [MCP Integration](https://tinyland.gitlab.io/projects/remote-juggler/integrations/mcp/)
- [Architecture](https://tinyland.gitlab.io/projects/remote-juggler/architecture/)

## Development

### Requirements

- Chapel 2.8+
- macOS: Xcode Command Line Tools (for Security.framework)
- Optional: glab CLI (GitLab operations)
- Optional: gh CLI (GitHub operations)

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

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- **Repository**: https://gitlab.com/tinyland/projects/remote-juggler
- **Documentation**: https://tinyland.gitlab.io/projects/remote-juggler
- **Issues**: https://gitlab.com/tinyland/projects/remote-juggler/-/issues
- **Releases**: https://gitlab.com/tinyland/projects/remote-juggler/-/releases
