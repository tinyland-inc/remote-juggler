# ACP Server

RemoteJuggler implements an Agent Communication Protocol (ACP) server for integration with JetBrains IDEs.

## Overview

ACP is a protocol used by JetBrains AI assistants to communicate with external agent servers. RemoteJuggler's ACP server provides the same tools as the MCP server but formatted for ACP protocol requirements.

**Implementation:** `src/remote_juggler/ACP.chpl`

## Starting the Server

```bash
remote-juggler --mode=acp
```

The server reads JSON-RPC messages from stdin and writes responses to stdout.

## Configuration

### JetBrains Global Configuration

Create or edit `~/.jetbrains/acp.json`:

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

### Per-IDE Configuration

For IntelliJ IDEA, configure in:
- macOS: `~/Library/Application Support/JetBrains/IntelliJIdea<version>/options/acp.json`
- Linux: `~/.config/JetBrains/IntelliJIdea<version>/options/acp.json`
- Windows: `%APPDATA%\JetBrains\IntelliJIdea<version>\options\acp.json`

## Protocol Details

ACP uses a similar message format to MCP but with some differences:

### Server Registration

```json
{
  "name": "RemoteJuggler",
  "version": "2.0.0",
  "description": "Git identity management for multi-account workflows",
  "tools": [...]
}
```

### Tool Invocation

ACP tool calls use the same schema as MCP but may include additional context:

```json
{
  "method": "executeAction",
  "params": {
    "tool": "juggler_switch",
    "arguments": {
      "identity": "work"
    },
    "context": {
      "projectPath": "/path/to/project",
      "language": "kotlin"
    }
  }
}
```

## Available Tools

The ACP server exposes the same tools as MCP:

| Tool | Description |
|------|-------------|
| `juggler_list_identities` | List configured identities |
| `juggler_detect_identity` | Detect identity for repository |
| `juggler_switch` | Switch to identity |
| `juggler_status` | Get current status |
| `juggler_validate` | Validate connectivity |
| `juggler_store_token` | Store token in Keychain |
| `juggler_sync_config` | Sync configuration |

See [MCP Server](mcp.md) for detailed tool schemas.

## Example Usage in JetBrains

### AI Assistant Chat

In JetBrains AI Assistant, you can invoke RemoteJuggler:

```
@RemoteJuggler switch to my work identity
```

The assistant will call the appropriate tool:

```json
{
  "tool": "juggler_switch",
  "arguments": {
    "identity": "work",
    "setRemote": true,
    "configureGPG": true
  }
}
```

### Action Results

Tool results are displayed in the AI Assistant panel:

```
Switched to identity: work
================================

[OK] Set user.name = jsullivan2
[OK] Set user.email = jsullivan2@bates.edu
[OK] Remote URL already correct: git@gitlab-work:bates-ils/project.git

Provider CLI Authentication:
[OK] glab authenticated to gitlab.com

Identity switch completed successfully.
```

## Debugging

### Enable Logging

Set environment variable:

```bash
REMOTE_JUGGLER_VERBOSE=1
```

Or configure in acp.json:

```json
{
  "agent_servers": {
    "RemoteJuggler": {
      "command": "remote-juggler",
      "args": ["--mode=acp", "--verbose"],
      "env": {
        "REMOTE_JUGGLER_VERBOSE": "1"
      }
    }
  }
}
```

### View Logs

JetBrains logs ACP communication in:
- macOS: `~/Library/Logs/JetBrains/<IDE>/acp.log`
- Linux: `~/.cache/JetBrains/<IDE>/log/acp.log`

## Comparison with MCP

| Aspect | MCP | ACP |
|--------|-----|-----|
| Primary Target | Claude Code | JetBrains IDEs |
| Protocol Base | JSON-RPC 2.0 | JSON-RPC 2.0 |
| Tool Schema | MCP format | Similar with extensions |
| Context | Working directory | Project context |
| Configuration | `.mcp.json` | `acp.json` |

Both protocols receive the same tool implementations, ensuring consistent behavior across all AI assistants.
