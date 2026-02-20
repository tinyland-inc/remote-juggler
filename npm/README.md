# @tinyland/remote-juggler

Multi-provider git identity management with MCP server support for AI agents.

## Quick Start

### As an MCP Server (for AI agents)

Add to your MCP client configuration (Claude Code, Cursor, VS Code):

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

### As a CLI Tool

```bash
npx @tinyland/remote-juggler list
npx @tinyland/remote-juggler switch gitlab-personal
npx @tinyland/remote-juggler status
```

### Full Installation

For a permanent installation with shell completions and IDE integration:

```bash
curl -fsSL https://raw.githubusercontent.com/Jesssullivan/RemoteJuggler/main/install.sh | bash
```

## What It Does

RemoteJuggler manages multiple git identities across providers (GitLab, GitHub, Bitbucket). It handles:

- SSH key selection per identity
- GPG signing configuration
- Git user.name/user.email switching
- Credential resolution (Keychain, env vars, SSH agent)
- Automatic identity detection from repository remotes

## MCP Tools

When running as an MCP server, these tools are available to AI agents:

| Tool | Description |
|------|-------------|
| `juggler_list_identities` | List all configured identities |
| `juggler_detect_identity` | Auto-detect identity from repo remote URL |
| `juggler_switch` | Switch to a different identity |
| `juggler_status` | Get current identity and git config status |
| `juggler_validate` | Test SSH/API connectivity for an identity |
| `juggler_store_token` | Store API token in keychain |
| `juggler_sync_config` | Synchronize managed SSH/git config blocks |

## Supported Platforms

- Linux x86_64
- Linux ARM64
- macOS x86_64 (Intel)
- macOS ARM64 (Apple Silicon)

## Links

- [GitHub Repository](https://github.com/Jesssullivan/RemoteJuggler)
- [Full Documentation](https://github.com/Jesssullivan/RemoteJuggler/blob/main/README.md)
- [MCP Registry](https://modelcontextprotocol.io)
