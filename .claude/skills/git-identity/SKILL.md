---
name: "git-identity"
description: "Automatically manages git identity switching across GitLab and GitHub accounts. Detects repository context, manages GPG signing, and handles credential resolution via keychain."
allowed-tools: "Read(...), Bash(...)"
---

## Git Identity Management with RemoteJuggler

This skill helps manage multiple git identities (personal, work, GitHub) seamlessly.

### When to activate:
- User mentions switching git accounts or identities
- Git push/pull fails with authentication errors
- Working with repositories from different organizations
- GPG signing issues or verification failures
- User asks about current git configuration
- Clone/push to a repository belonging to a different account
- Authentication token errors or credential issues

### Available commands:
- `remote-juggler status` - Current identity and repository info
- `remote-juggler list` - All configured identities
- `remote-juggler detect` - Auto-detect appropriate identity
- `remote-juggler switch <name>` - Switch to identity
- `remote-juggler validate <name>` - Test SSH/API connectivity
- `remote-juggler gpg verify` - Check GPG key registration
- `remote-juggler token verify` - Test all stored credentials
- `remote-juggler config sync` - Sync from SSH/git configs

### Identity resolution:
1. Parse git remote URL to identify provider (GitLab/GitHub)
2. Match organization path to configured identity
3. Suggest or perform identity switch
4. Configure GPG signing if enabled

### Credential priority:
1. Darwin Keychain (macOS)
2. Environment variables
3. glab/gh CLI stored auth
4. SSH-only fallback

### Common scenarios:

**Authentication failure during push:**
```bash
# Detect which identity should be used
remote-juggler detect

# Switch to the correct identity
remote-juggler switch <detected-identity>

# Retry the git operation
git push
```

**Working with multiple organizations:**
```bash
# Check current identity
remote-juggler status

# If mismatched, switch to correct identity
remote-juggler switch work

# Verify connectivity
remote-juggler validate work
```

**GPG signing not working:**
```bash
# Check GPG configuration
remote-juggler gpg verify

# The output will show if key is registered with provider
# and provide URL to add it if missing
```

### Provider-specific notes:

**GitLab:**
- Uses `glab` CLI for API operations
- Supports multiple hosts (gitlab.com, self-hosted)
- Tokens stored with service name `remote-juggler.gitlab.<identity>`

**GitHub:**
- Uses `gh` CLI for API operations
- Supports GitHub Enterprise
- Tokens stored with service name `remote-juggler.github.<identity>`

### Configuration location:
- Config file: `~/.config/remote-juggler/config.json`
- Managed blocks auto-sync from `~/.ssh/config` and `~/.gitconfig`
