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

```sh
curl -fsSL https://raw.githubusercontent.com/tinyland-inc/remote-juggler/main/install.sh | sh
```

The script performs these operations:

1. Detects platform (darwin/linux, amd64/arm64)
2. Downloads binary from GitLab releases or GitHub
3. Installs to `~/.local/bin` (or first available in PATH)
4. Initializes configuration at `~/.config/remote-juggler/config.json`
5. Imports identities from `~/.ssh/config`
6. Configures Claude Code slash commands

The script is POSIX-compatible and works with any POSIX shell (`sh`, `bash`, `dash`, `zsh`, etc.).

### Version Selection

Override the default version:

```sh
REMOTE_JUGGLER_VERSION=2.0.1 curl -fsSL https://raw.githubusercontent.com/tinyland-inc/remote-juggler/main/install.sh | sh
```

Or use the `--version` flag when running the script directly:

```sh
sh install.sh --version 2.0.1
```

### Uninstall via Script

```bash
curl -fsSL https://get.remote-juggler.dev | bash -s -- --uninstall
```

## Package Managers

### Homebrew (macOS/Linux)

Install via the Tinyland Homebrew tap:

```bash
# Add the tap
brew tap tinyland/tools https://github.com/tinyland-inc/homebrew-tap.git

# Install
brew install remote-juggler

# Update
brew upgrade remote-juggler
```

#### Shell Completions

Homebrew automatically installs shell completions. To enable them:

```bash
# Bash (add to ~/.bashrc)
source $(brew --prefix)/etc/bash_completion.d/remote-juggler.bash

# Zsh (add to ~/.zshrc)
fpath=($(brew --prefix)/share/zsh/site-functions $fpath)
autoload -Uz compinit && compinit

# Fish - completions auto-load
```

### Arch Linux (AUR)

```bash
# With yay
yay -S remote-juggler

# Or build manually
git clone https://aur.archlinux.org/remote-juggler.git
cd remote-juggler
makepkg -si
```

### Debian/Ubuntu

```bash
# Download .deb package from releases
curl -LO https://github.com/tinyland-inc/remote-juggler/releases/download/vX.Y.Z/remote-juggler_X.Y.Z_amd64.deb

# Install
sudo dpkg -i remote-juggler_X.Y.Z_amd64.deb
sudo apt-get install -f  # Fix dependencies if needed
```

### Fedora/RHEL/Rocky

```bash
# Download .rpm package from releases
curl -LO https://github.com/tinyland-inc/remote-juggler/releases/download/vX.Y.Z/remote-juggler-X.Y.Z-1.x86_64.rpm

# Install
sudo dnf install remote-juggler-X.Y.Z-1.x86_64.rpm
```

### Nix

```bash
# Ephemeral (try it out)
nix run github:tinyland-inc/remote-juggler

# Install to profile
nix profile install github:tinyland-inc/remote-juggler

# In flake.nix
{
  inputs.remote-juggler.url = "github:tinyland-inc/remote-juggler";
  # ...
  environment.systemPackages = [ inputs.remote-juggler.packages.${system}.default ];
}
```

### Flatpak

```bash
# Add Flathub (if not already)
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install
flatpak install flathub dev.tinyland.RemoteJuggler

# Run
flatpak run dev.tinyland.RemoteJuggler
```

## Binary Download

Download pre-built binaries from the [Releases page](https://github.com/tinyland-inc/remote-juggler/releases):

| Platform | Architecture | Download |
|----------|--------------|----------|
| macOS | Apple Silicon | `remote-juggler-X.Y.Z-darwin-arm64.tar.gz` |
| macOS | Intel | `remote-juggler-X.Y.Z-darwin-amd64.tar.gz` |
| Linux | x86_64 | `remote-juggler-X.Y.Z-linux-amd64.tar.gz` |
| Linux | ARM64 | `remote-juggler-X.Y.Z-linux-arm64.tar.gz` |

```bash
# Example: Download and install
curl -LO https://github.com/tinyland-inc/remote-juggler/releases/download/vX.Y.Z/remote-juggler-X.Y.Z-linux-amd64.tar.gz
tar -xzf remote-juggler-X.Y.Z-linux-amd64.tar.gz
mv remote-juggler ~/.local/bin/
chmod +x ~/.local/bin/remote-juggler
```

### Verify Downloads

Always verify downloads before installation:

```bash
# Download checksums and signature
curl -LO https://gitlab.com/.../SHA256SUMS.txt
curl -LO https://gitlab.com/.../SHA256SUMS.txt.asc

# Import GPG key and verify
curl -fsSL https://gitlab.com/.../keys/release-signing.asc | gpg --import
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt
sha256sum -c SHA256SUMS.txt --ignore-missing
```

### macOS DMG Installer

1. Download `RemoteJuggler-X.Y.Z.dmg`
2. Open DMG and drag to Applications
3. First launch: Right-click then Open (bypasses Gatekeeper)

### Linux AppImage

```bash
curl -LO https://gitlab.com/.../RemoteJuggler-x86_64.AppImage
chmod +x RemoteJuggler-x86_64.AppImage
./RemoteJuggler-x86_64.AppImage
```

## Build from Source

Building requires Chapel 2.6.0 or later.

```bash
# Clone repository
git clone https://github.com/tinyland-inc/remote-juggler.git
cd remote-juggler

# Build with just
just build    # Debug build -> target/debug/
just release  # Optimized build -> target/release/

# Or use Mason (Chapel package manager)
mason build --release

# Install to ~/.local/bin
just install
```

### Build Prerequisites

| Dependency | Version | Purpose |
|------------|---------|---------|
| Chapel | 2.6+ | Main CLI compiler |
| Rust | 1.75+ | GTK GUI (optional) |
| Go | 1.21+ | Linux tray app (optional) |
| Swift | 5.9+ | macOS tray app (optional) |
| TPM2-TSS | 4.0+ | TPM support (Linux, optional) |

### macOS Build Requirements

macOS builds link against Security.framework for Keychain integration. The Makefile handles this automatically:

```makefile
ifeq ($(UNAME_S),Darwin)
  CHPL_LDFLAGS = --ldflags="-framework Security -framework CoreFoundation"
endif
```

### Build with Nix

```bash
# Enter development shell
nix develop

# Build all packages
nix build .#remote-juggler
nix build .#pinentry-remotejuggler
nix build .#remote-juggler-gui

# Build for specific platform
nix build .#packages.x86_64-linux.remote-juggler
nix build .#packages.aarch64-darwin.remote-juggler
```

## Installation Locations

The install script searches for directories in PATH:

1. `~/.local/bin` (preferred)
2. `~/bin`
3. `~/.bin`

If none exist, it creates `~/.local/bin` and prompts you to add it to PATH.

## Configuration Directory

Configuration files are stored following XDG Base Directory spec:

```
${XDG_CONFIG_HOME:-$HOME/.config}/remote-juggler/
  config.json       # Main configuration
```

## IDE Integration

### Claude Code

The installer creates slash commands at `~/.claude/commands/`:

- `/juggle <identity>` - Switch identity
- `/identity <action>` - List/detect/validate identities
- `/remotes` - View remote configuration

Add to your `.mcp.json` for MCP tool access:

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

### JetBrains

For IntelliJ-based IDEs, add to `~/.jetbrains/acp.json`:

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

If macOS blocks the binary ("App is damaged and can't be opened"):

```bash
xattr -d com.apple.quarantine ~/.local/bin/remote-juggler
```

Verify code signature:

```bash
codesign -dv --verbose=4 /usr/local/bin/remote-juggler
spctl -a -vvv -t install RemoteJuggler.app
```

### Linux: Missing shared libraries

```bash
# Check dependencies
ldd $(which remote-juggler)

# Install missing libraries
sudo apt install libgcc-s1  # Debian/Ubuntu
sudo dnf install libgcc     # Fedora
```

### Flatpak: Can't access SSH keys

Flatpak sandboxing may prevent SSH access. Grant permissions:

```bash
flatpak override --user --filesystem=~/.ssh:ro dev.tinyland.RemoteJuggler
```
