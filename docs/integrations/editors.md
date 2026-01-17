---
title: "Editor Setup"
description: "Configure RemoteJuggler MCP/ACP integration for VS Code, Cursor, Windsurf, JetBrains, Neovim, and other editors."
category: "operations"
llm_priority: 3
keywords:
  - editor
  - vscode
  - jetbrains
  - cursor
  - neovim
---

# Editor Setup

Configure RemoteJuggler for various editors and AI assistants.

## VS Code / Cursor

### MCP Extension Configuration

Create `.vscode/mcp.json` or project-level `.mcp.json`:

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

### Cursor Configuration

Cursor uses the same MCP configuration. Add to your Cursor settings:

1. Open Settings (Cmd/Ctrl + ,)
2. Search for "MCP"
3. Add RemoteJuggler to MCP servers

Or create `~/.cursor/mcp.json`:

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

## Windsurf

Windsurf supports MCP servers. Add to your Windsurf configuration:

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

## Claude Desktop

For the Claude desktop application, configure MCP servers in:

**macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "remote-juggler": {
      "command": "/Users/<username>/.local/bin/remote-juggler",
      "args": ["--mode=mcp"]
    }
  }
}
```

Use the full path to the binary for desktop applications.

## Zed

Zed supports MCP through its assistant feature. Configure in settings:

```json
{
  "assistant": {
    "mcp_servers": {
      "remote-juggler": {
        "command": "remote-juggler",
        "args": ["--mode=mcp"]
      }
    }
  }
}
```

## JetBrains IDEs

### Global Configuration

Create `~/.jetbrains/acp.json`:

```json
{
  "agent_servers": {
    "RemoteJuggler": {
      "command": "remote-juggler",
      "args": ["--mode=acp"],
      "env": {},
      "use_idea_mcp": false,
      "use_custom_mcp": false
    }
  }
}
```

### Supported IDEs

- IntelliJ IDEA
- PyCharm
- WebStorm
- GoLand
- CLion
- Rider
- DataGrip
- RubyMine
- PhpStorm

All JetBrains IDEs use the same ACP configuration format.

## Neovim

For Neovim with an MCP plugin, configure in your init.lua:

```lua
require('mcp').setup({
  servers = {
    ['remote-juggler'] = {
      command = 'remote-juggler',
      args = {'--mode=mcp'},
    },
  },
})
```

## Emacs

For Emacs with an MCP package:

```elisp
(use-package mcp
  :config
  (add-to-list 'mcp-servers
    '("remote-juggler" . (:command "remote-juggler" :args ("--mode=mcp")))))
```

## Generic MCP Client

Any MCP-compatible client can use RemoteJuggler:

```bash
# Spawn the server
remote-juggler --mode=mcp

# Send JSON-RPC messages via stdin
# Receive responses via stdout
```

Example initialization:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}
```

## Verifying Integration

### Test MCP Server

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}' | \
  remote-juggler --mode=mcp
```

Expected response includes server info and capabilities.

### Test Tool Call

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | \
  remote-juggler --mode=mcp
```

Should return list of available tools.

## Troubleshooting

### Server Not Found

Ensure RemoteJuggler is in your PATH:

```bash
which remote-juggler
```

If not found, use the full path in configuration:

```json
{
  "command": "/Users/<username>/.local/bin/remote-juggler"
}
```

### Permission Denied

Make the binary executable:

```bash
chmod +x ~/.local/bin/remote-juggler
```

### No Response

Check server stderr for errors:

```bash
remote-juggler --mode=mcp 2>debug.log
```

### Keychain Access Denied

On macOS, you may need to grant Keychain access. A system prompt should appear on first token access.
