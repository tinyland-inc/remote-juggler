# CLI Reference

RemoteJuggler provides a comprehensive command-line interface for managing git identities.

## Synopsis

```
remote-juggler [OPTIONS] <COMMAND> [ARGS]
```

## Global Options

| Option | Description |
|--------|-------------|
| `--mode=<mode>` | Operation mode: `cli` (default), `mcp`, `acp` |
| `--verbose` | Enable verbose debug output |
| `--help` | Show help message |
| `--configPath=<path>` | Override config file path |
| `--useKeychain` | Enable/disable macOS Keychain (default: true) |
| `--gpgSign` | Enable/disable GPG signing (default: true) |
| `--provider=<p>` | Filter by provider: `gitlab`, `github`, `bitbucket`, `all` |

## Command Categories

### Identity Management

Commands for listing, detecting, and switching identities.

- `list` - List all configured identities
- `detect` - Detect identity for current repository
- `switch <name>` - Switch to identity
- `validate <name>` - Test SSH/API connectivity
- `status` - Show current identity status

### Configuration

Commands for managing the configuration file.

- `config show` - Display configuration
- `config add <name>` - Add new identity
- `config edit <name>` - Edit existing identity
- `config remove <name>` - Remove identity
- `config import` - Import from SSH config
- `config sync` - Synchronize managed blocks

### Token Management

Commands for credential storage (macOS only).

- `token set <name>` - Store token in Keychain
- `token get <name>` - Retrieve token (masked)
- `token clear <name>` - Remove token
- `token verify` - Test all credentials

### GPG Signing

Commands for GPG key configuration.

- `gpg status` - Show GPG configuration
- `gpg configure <name>` - Configure GPG for identity
- `gpg verify` - Check provider registration

### Debug

Commands for troubleshooting.

- `debug ssh-config` - Show parsed SSH configuration
- `debug git-config` - Show parsed gitconfig rewrites
- `debug keychain` - Test Keychain access

## Server Modes

RemoteJuggler can run as an agent protocol server:

```bash
# MCP server for Claude Code, VS Code, Cursor
remote-juggler --mode=mcp

# ACP server for JetBrains IDEs
remote-juggler --mode=acp
```

See [Commands](commands.md) for detailed command reference.
