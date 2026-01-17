# RemoteJuggler Project Instructions

## Overview

RemoteJuggler is a Chapel-based git identity management tool supporting MCP/ACP protocols. It enables seamless switching between multiple git identities (personal, work, different providers) with automatic credential resolution, GPG signing configuration, and IDE integration.

## Build Commands

```bash
# Debug build
mason build

# Release build (optimized)
mason build --release

# Run tests
mason test

# Clean build artifacts
mason clean
```

## Project Structure

```
remote-juggler/
├── src/
│   ├── remote_juggler.chpl           # Main entry point + CLI
│   └── remote_juggler/
│       ├── Core.chpl                 # Core types and constants
│       ├── Identity.chpl             # SSH/Git identity management
│       ├── Config.chpl               # SSH config & gitconfig parsing
│       ├── GlobalConfig.chpl         # Global config with managed blocks
│       ├── Remote.chpl               # Git remote operations
│       ├── State.chpl                # Context persistence
│       ├── Keychain.chpl             # Darwin Keychain integration (C FFI)
│       ├── ProviderCLI.chpl          # glab/gh CLI abstraction layer
│       ├── GPG.chpl                  # GPG signing integration
│       ├── Protocol.chpl             # JSON-RPC message handling
│       ├── MCP.chpl                  # MCP server implementation
│       ├── ACP.chpl                  # ACP server implementation
│       └── Tools.chpl                # Tool definitions & handlers
├── c_src/
│   └── keychain_darwin.c             # macOS Security.framework bindings
├── test/
│   └── *.chpl                        # Test files
├── Mason.toml                        # Chapel package manifest
└── install.sh                        # Rootless installer
```

## MCP Server

The tool can run as an MCP server for AI agent integration:

```bash
# Start MCP server (STDIO transport)
remote-juggler --mode=mcp
```

MCP tools provided:
- `juggler_list_identities` - List configured identities
- `juggler_detect_identity` - Detect repo identity from remote URL
- `juggler_switch` - Switch to a different identity
- `juggler_status` - Get current identity status
- `juggler_validate` - Test SSH/API connectivity
- `juggler_store_token` - Store token in keychain
- `juggler_sync_config` - Sync managed blocks

## ACP Server

For JetBrains IDE integration:

```bash
# Start ACP server (STDIO transport)
remote-juggler --mode=acp
```

## Development Notes

### Requirements
- Chapel 2.8+ required
- macOS: Xcode Command Line Tools (for Security.framework)
- Optional: glab CLI (GitLab operations)
- Optional: gh CLI (GitHub operations)

### C FFI for Darwin Keychain
The `c_src/keychain_darwin.c` file provides bindings to macOS Security.framework. These are conditionally compiled only on Darwin platforms.

### JSON-RPC 2.0
Both MCP and ACP use JSON-RPC 2.0 over STDIO. The Protocol.chpl module handles message parsing and serialization.

### Testing
```bash
# Run all tests
mason test

# Run specific test
mason test --test=TestIdentity

# Test MCP protocol compliance
./scripts/test-mcp-protocol.sh
```

## CLI Usage

```bash
# Show current status
remote-juggler

# List all identities
remote-juggler list

# Detect identity for current repo
remote-juggler detect

# Switch identity
remote-juggler switch personal

# Validate connectivity
remote-juggler validate work

# Store token in keychain (Darwin)
remote-juggler token set personal

# Verify all credentials
remote-juggler token verify

# Sync config from SSH/git
remote-juggler config sync
```

## Configuration

Config location: `~/.config/remote-juggler/config.json`

The config file contains:
- Identity definitions (provider, host, user, email, SSH key, credentials)
- Managed blocks (auto-synced from ~/.ssh/config and ~/.gitconfig)
- GPG signing configuration per identity
- Global settings

## Credential Resolution Order

1. Darwin Keychain (macOS) - Service: `remote-juggler.<provider>.<identity>`
2. Environment variable - `${IDENTITY}_TOKEN` or custom
3. Provider CLI stored auth - `glab auth token` / `gh auth token`
4. SSH-only fallback - No token, git operations via SSH only

## IDE Integration Files

- `.mcp.json` - MCP server configuration for Claude Code
- `acp.json` - ACP server configuration for JetBrains
- `.claude/commands/` - Slash commands for Claude Code
- `.claude/skills/git-identity/` - Auto-invocable skill
