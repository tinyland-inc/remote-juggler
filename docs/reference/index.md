# Reference

API and schema reference documentation.

## Contents

- [MCP Tool Schemas](tools-schema.md) - JSON schemas for MCP tools
- [Configuration Schema](config-schema.md) - config.json file format
- [Environment Variables](environment.md) - Environment configuration

## Quick Reference

### MCP Tools

| Tool | Purpose |
|------|---------|
| `juggler_list_identities` | List configured identities |
| `juggler_detect_identity` | Detect identity for repository |
| `juggler_switch` | Switch to identity |
| `juggler_status` | Get current status |
| `juggler_validate` | Validate connectivity |
| `juggler_store_token` | Store token in Keychain |
| `juggler_sync_config` | Sync configuration |

### Configuration Fields

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Config schema version |
| `identities` | object | Map of identity configurations |
| `settings` | object | Global settings |
| `state` | object | Runtime state |

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `REMOTE_JUGGLER_CONFIG` | Override config path |
| `REMOTE_JUGGLER_VERBOSE` | Enable debug output |
| `NO_COLOR` | Disable colored output |
| `GITLAB_TOKEN` | GitLab API token |
| `GITHUB_TOKEN` | GitHub API token |
