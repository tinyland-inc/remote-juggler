---
title: "Installation"
description: "Multi-platform installation instructions for RemoteJuggler including automated install, binary download, building from source, and IDE integration setup."
category: "operations"
llm_priority: 3
keywords:
  - install
  - download
  - binary
  - build
  - macos
  - linux
---

# Installation

RemoteJuggler provides multiple installation methods for different platforms and use cases.

## Automated Installation (Recommended)

The install script handles platform detection and configuration:

```bash
curl -sSL https://gitlab.com/tinyland/projects/remote-juggler/-/raw/main/install.sh | bash
```

The script performs these operations (see `install.sh:446-454`):

1. Detects platform (darwin/linux, amd64/arm64)
2. Downloads binary from GitLab releases or GitHub
3. Installs to `~/.local/bin` (or first available in PATH)
4. Initializes configuration at `~/.config/remote-juggler/config.json`
5. Imports identities from `~/.ssh/config`
6. Configures Claude Code slash commands

### Version Selection

Override the default version:

```bash
REMOTE_JUGGLER_VERSION=2.0.1 curl -sSL .../install.sh | bash
```

## Binary Download

Download pre-built binaries directly:

| Platform | Architecture | Download |
|----------|--------------|----------|
| macOS | arm64 | `remote-juggler-darwin-arm64` |
| macOS | amd64 | `remote-juggler-darwin-amd64` |
| Linux | amd64 | `remote-juggler-linux-amd64` |

```bash
# Example: macOS arm64
curl -L https://gitlab.com/tinyland/projects/remote-juggler/-/releases/v2.0.0/downloads/remote-juggler-darwin-arm64 \
  -o ~/.local/bin/remote-juggler
chmod +x ~/.local/bin/remote-juggler
```

## Build from Source

Building requires Chapel 2.6.0 or later:

```bash
# Clone repository
git clone https://gitlab.com/tinyland/projects/remote-juggler.git
cd remote-juggler

# Build with make
make build    # Debug build -> target/debug/
make release  # Optimized build -> target/release/

# Or use Mason (Chapel package manager)
mason build --release
```

### macOS Build Requirements

macOS builds link against Security.framework for Keychain integration. The Makefile handles this automatically (see `Makefile:8-12`):

```makefile
ifeq ($(UNAME_S),Darwin)
  CHPL_LDFLAGS = --ldflags="-framework Security -framework CoreFoundation"
endif
```

## Installation Locations

The install script searches for directories in PATH (`install.sh:58-62`):

1. `~/.local/bin` (preferred)
2. `~/bin`
3. `~/.bin`

If none exist, it creates `~/.local/bin` and prompts you to add it to PATH.

## Configuration Directory

Configuration files are stored following XDG Base Directory spec (`install.sh:65`):

```
${XDG_CONFIG_HOME:-$HOME/.config}/remote-juggler/
  config.json       # Main configuration
```

## IDE Integration

### Claude Code

The installer creates slash commands at `~/.claude/commands/` (`install.sh:218-282`):

- `/juggle <identity>` - Switch identity
- `/identity <action>` - List/detect/validate identities
- `/remotes` - View remote configuration

### JetBrains

For IntelliJ-based IDEs, add to `~/.jetbrains/acp.json` (`install.sh:345-358`):

```json
{
  "agent_servers": {
    "RemoteJuggler": {
      "command": "remote-juggler",
      "args": ["--mode=acp"]
    }
  }
}
```

## Uninstallation

Remove the binary and configuration:

```bash
rm ~/.local/bin/remote-juggler
rm -rf ~/.config/remote-juggler
rm ~/.claude/commands/{juggle,identity,remotes}.md
```

## Troubleshooting

### Binary not found after install

Add the install directory to your PATH:

```bash
# bash/zsh
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc

# fish
fish_add_path ~/.local/bin
```

### Permission denied

Ensure the binary is executable:

```bash
chmod +x ~/.local/bin/remote-juggler
```

### macOS Gatekeeper warning

If macOS blocks the binary:

```bash
xattr -d com.apple.quarantine ~/.local/bin/remote-juggler
```
