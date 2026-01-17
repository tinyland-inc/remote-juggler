# Environment Variables

Environment variables for configuring RemoteJuggler.

## Configuration Variables

### REMOTE_JUGGLER_CONFIG

Override the configuration file path.

```bash
export REMOTE_JUGGLER_CONFIG="/path/to/custom/config.json"
```

Default: `~/.config/remote-juggler/config.json`

### REMOTE_JUGGLER_VERBOSE

Enable verbose debug output.

```bash
export REMOTE_JUGGLER_VERBOSE=1
```

Equivalent to `--verbose` flag.

### NO_COLOR

Disable colored output (follows [no-color.org](https://no-color.org) standard).

```bash
export NO_COLOR=1
```

## Token Variables

### Provider-Specific Tokens

| Variable | Provider | Description |
|----------|----------|-------------|
| `GITLAB_TOKEN` | GitLab | GitLab personal access token |
| `GITHUB_TOKEN` | GitHub | GitHub personal access token |
| `BITBUCKET_TOKEN` | Bitbucket | Bitbucket app password |

### Identity-Specific Tokens

Configure per-identity tokens via `tokenEnvVar` in config:

```json
{
  "identities": {
    "work": {
      "tokenEnvVar": "GITLAB_WORK_TOKEN"
    }
  }
}
```

Then set:

```bash
export GITLAB_WORK_TOKEN="glpat-xxxxxxxxxxxx"
```

## Credential Resolution Order

RemoteJuggler resolves credentials in this order:

1. **macOS Keychain** (if `useKeychain: true`)
2. **Identity-specific environment variable** (if `tokenEnvVar` configured)
3. **Provider environment variable** (`GITLAB_TOKEN`, etc.)
4. **CLI authentication** (glab/gh stored credentials)
5. **SSH-only mode** (if `fallbackToSSH: true`)

## Shell Configuration

### Bash

Add to `~/.bashrc`:

```bash
# RemoteJuggler configuration
export PATH="$PATH:$HOME/.local/bin"

# Optional: Per-identity tokens
export GITLAB_WORK_TOKEN="glpat-work-token"
export GITLAB_PERSONAL_TOKEN="glpat-personal-token"
export GITHUB_TOKEN="ghp-github-token"

# Optional: Verbose mode
# export REMOTE_JUGGLER_VERBOSE=1
```

### Zsh

Add to `~/.zshrc`:

```zsh
# RemoteJuggler configuration
path+=("$HOME/.local/bin")

# Optional: Per-identity tokens
export GITLAB_WORK_TOKEN="glpat-work-token"
export GITLAB_PERSONAL_TOKEN="glpat-personal-token"
export GITHUB_TOKEN="ghp-github-token"
```

### Fish

Add to `~/.config/fish/config.fish`:

```fish
# RemoteJuggler configuration
fish_add_path ~/.local/bin

# Optional: Per-identity tokens
set -gx GITLAB_WORK_TOKEN "glpat-work-token"
set -gx GITLAB_PERSONAL_TOKEN "glpat-personal-token"
set -gx GITHUB_TOKEN "ghp-github-token"
```

## CI/CD Variables

### GitLab CI

Set as protected/masked variables:

```yaml
variables:
  GITLAB_TOKEN: $CI_JOB_TOKEN  # Built-in
  # Or use custom variable from CI/CD settings
```

### GitHub Actions

Set as repository secrets:

```yaml
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## MCP Server Environment

When running as MCP server, environment is inherited from parent process.

### Claude Code

Ensure variables are set before starting Claude Code:

```bash
export GITLAB_TOKEN="glpat-xxxx"
code .
```

### JetBrains

Configure in `acp.json`:

```json
{
  "agent_servers": {
    "RemoteJuggler": {
      "command": "remote-juggler",
      "args": ["--mode=acp"],
      "env": {
        "REMOTE_JUGGLER_VERBOSE": "1"
      }
    }
  }
}
```

## XDG Base Directory

RemoteJuggler follows XDG Base Directory specification:

| Variable | Default | Usage |
|----------|---------|-------|
| `XDG_CONFIG_HOME` | `~/.config` | Configuration directory |

Configuration path:
```
${XDG_CONFIG_HOME:-$HOME/.config}/remote-juggler/config.json
```

## Debugging

### List Relevant Variables

```bash
env | grep -E 'REMOTE_JUGGLER|GITLAB|GITHUB|BITBUCKET|XDG'
```

### Test Token Availability

```bash
# Check if token is set
[ -n "$GITLAB_TOKEN" ] && echo "GITLAB_TOKEN is set" || echo "GITLAB_TOKEN not set"
```

### Verify Credential Resolution

```bash
remote-juggler --verbose token verify
```

Shows which credential source is used for each identity.
