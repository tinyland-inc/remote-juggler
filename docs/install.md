# Install RemoteJuggler

Choose the installation method that matches your platform and workflow.

## Quick Install (Recommended)

One-liner for macOS and Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/Jesssullivan/RemoteJuggler/main/install.sh | sh
```

This installs the CLI binary, configures shell completions, and sets up MCP server entries for supported AI agent clients.

## npm / npx

Works on any platform with Node.js 18+:

```bash
# Install globally
npm install -g @tinyland/remote-juggler

# Or run directly without installing
npx @tinyland/remote-juggler --version
npx @tinyland/remote-juggler --mode=mcp
```

## Homebrew (macOS / Linux)

```bash
brew tap tinyland/tools https://github.com/Jesssullivan/homebrew-tap.git
brew install remote-juggler
```

## Nix

```bash
# Try it without installing
nix run github:Jesssullivan/RemoteJuggler -- --version

# Install to profile
nix profile install github:Jesssullivan/RemoteJuggler

# Use in a flake
# flake.nix inputs:
#   inputs.remote-juggler.url = "github:Jesssullivan/RemoteJuggler";
```

### Nix Home Manager

```nix
# In your Home Manager configuration:
imports = [ inputs.remote-juggler.homeManagerModules.default ];

programs.remote-juggler = {
  enable = true;
  gui.enable = true;   # GTK4 GUI (Linux only)
  mcp.enable = true;   # Configure MCP for AI agents
  mcp.clients = [ "claude-code" "cursor" "vscode" ];
};
```

## Debian / Ubuntu

```bash
curl -LO https://github.com/Jesssullivan/RemoteJuggler/releases/latest/download/remote-juggler_amd64.deb
sudo dpkg -i remote-juggler_amd64.deb
```

## RHEL / Rocky / Fedora

```bash
curl -LO https://github.com/Jesssullivan/RemoteJuggler/releases/latest/download/remote-juggler_x86_64.rpm
sudo rpm -i remote-juggler_x86_64.rpm
```

## AUR (Arch Linux)

```bash
yay -S remote-juggler
```

## Flatpak

```bash
flatpak install dev.tinyland.RemoteJuggler
```

## From Source

Requires [Chapel](https://chapel-lang.org/) 2.6+:

```bash
git clone https://github.com/Jesssullivan/RemoteJuggler.git
cd RemoteJuggler
just release
# Binary at target/release/remote_juggler
```

---

## AI Agent Setup

RemoteJuggler includes a built-in MCP (Model Context Protocol) server with 32 tools for AI-assisted git identity management.

### Claude Code

The install script automatically configures Claude Code. To set up manually:

```json
// .mcp.json (project or ~/.claude/.mcp.json)
{
  "mcpServers": {
    "remote-juggler": {
      "command": "remote-juggler",
      "args": ["--mode=mcp"]
    }
  }
}
```

### Cursor / VS Code / Windsurf

Add to your MCP configuration:

=== "Cursor (~/.cursor/mcp.json)"

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

=== "VS Code (~/.config/Code/User/mcp.json)"

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

=== "Windsurf (~/.windsurf/mcp.json)"

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

### JetBrains (ACP)

```json
// ~/.jetbrains/acp.json
{
  "servers": {
    "remote-juggler": {
      "command": "remote-juggler",
      "args": ["--mode=acp"]
    }
  }
}
```

### npx (Zero-Install MCP)

For environments without a persistent installation:

```json
{
  "mcpServers": {
    "remote-juggler": {
      "command": "npx",
      "args": ["-y", "@tinyland/remote-juggler", "--mode=mcp"]
    }
  }
}
```

---

## Verify Installation

```bash
remote-juggler --version
remote-juggler status
remote-juggler list
```
