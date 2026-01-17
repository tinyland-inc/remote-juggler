# SSH Configuration

Managing SSH host aliases for git identity separation.

## Overview

SSH host aliases allow multiple git accounts on the same provider by using different SSH keys per identity.

## SSH Config Structure

### Example Configuration

`~/.ssh/config`:

```
# Work GitLab
Host gitlab-work
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes

# Personal GitLab
Host gitlab-personal
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal
    IdentitiesOnly yes

# GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
    IdentitiesOnly yes
```

### Key Directives

| Directive | Purpose |
|-----------|---------|
| `Host` | Alias name used in git remote URLs |
| `HostName` | Actual hostname to connect to |
| `User` | SSH user (always "git" for git hosting) |
| `IdentityFile` | Path to SSH private key |
| `IdentitiesOnly` | Only use specified key, not SSH agent |

## Generating SSH Keys

### Create Key Per Identity

```bash
# Work key
ssh-keygen -t ed25519 -C "work@company.com" -f ~/.ssh/id_ed25519_work

# Personal key
ssh-keygen -t ed25519 -C "personal@email.com" -f ~/.ssh/id_ed25519_personal
```

### Add to SSH Agent

```bash
# Start agent
eval "$(ssh-agent -s)"

# Add keys
ssh-add ~/.ssh/id_ed25519_work
ssh-add ~/.ssh/id_ed25519_personal
```

## Provider Key Registration

### GitLab

1. Copy public key: `cat ~/.ssh/id_ed25519_work.pub`
2. Go to GitLab > Settings > SSH Keys
3. Paste key and add

### GitHub

1. Copy public key: `cat ~/.ssh/id_ed25519_github.pub`
2. Go to GitHub > Settings > SSH and GPG keys
3. Click "New SSH key" and paste

## RemoteJuggler Integration

### Importing SSH Config

RemoteJuggler imports identities from SSH config:

```bash
remote-juggler config import
```

This:
1. Parses `~/.ssh/config`
2. Finds git-related hosts (gitlab.com, github.com, bitbucket.org)
3. Creates identity entries for each

### Managed Blocks

RemoteJuggler can manage parts of your SSH config:

```
# BEGIN REMOTE-JUGGLER MANAGED
Host gitlab-work
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes
# END REMOTE-JUGGLER MANAGED
```

Synchronize with:

```bash
remote-juggler config sync
```

## URL Formats

### SSH URL with Alias

```
git@gitlab-work:company/project.git
```

Breakdown:
- `git@` - SSH user
- `gitlab-work` - SSH host alias
- `company/project.git` - Repository path

### Standard SSH URL

```
git@gitlab.com:user/repo.git
```

### HTTPS URL

```
https://gitlab.com/user/repo.git
```

RemoteJuggler transforms HTTPS to SSH alias format when switching identities.

## Testing SSH Connectivity

### Test Specific Host

```bash
ssh -T git@gitlab-work
```

Expected output:
```
Welcome to GitLab, @username!
```

### Debug Connection

```bash
ssh -vT git@gitlab-work
```

Shows detailed connection information including which key is used.

### RemoteJuggler Validation

```bash
remote-juggler validate work
```

Tests:
- SSH connection to host alias
- Authentication success
- Credential availability

## Troubleshooting

### "Permission denied (publickey)"

SSH key not found or not accepted:

```bash
# Check key exists
ls -la ~/.ssh/id_ed25519_work*

# Check key is added to agent
ssh-add -l

# Check key permissions
chmod 600 ~/.ssh/id_ed25519_work
chmod 644 ~/.ssh/id_ed25519_work.pub
```

### "Could not resolve hostname"

SSH config not loaded:

```bash
# Check config syntax
ssh -T -F ~/.ssh/config git@gitlab-work

# Check Host entry exists
grep -A5 "Host gitlab-work" ~/.ssh/config
```

### Wrong Key Used

Multiple keys being offered:

```bash
# Add IdentitiesOnly directive
Host gitlab-work
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes  # Important!
```

### Agent Forwarding Issues

For accessing git from remote servers:

```bash
# Enable agent forwarding
Host jumpbox
    HostName jumpbox.company.com
    ForwardAgent yes

Host gitlab-work
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    ProxyJump jumpbox
```

## Advanced Configuration

### Multiple Providers

```
# GitLab (work)
Host gitlab-work
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_gitlab_work

# GitLab (personal)
Host gitlab-personal
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_gitlab_personal

# Self-hosted GitLab
Host gitlab-company
    HostName gitlab.company.com
    User git
    IdentityFile ~/.ssh/id_ed25519_company

# GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github

# Bitbucket
Host bitbucket.org
    HostName bitbucket.org
    User git
    IdentityFile ~/.ssh/id_ed25519_bitbucket
```

### Non-Standard Ports

```
Host gitlab-internal
    HostName gitlab.internal.company.com
    Port 2222
    User git
    IdentityFile ~/.ssh/id_ed25519_internal
```

### ProxyJump for Bastion Access

```
Host gitlab-private
    HostName gitlab.private.network
    User git
    IdentityFile ~/.ssh/id_ed25519_private
    ProxyJump bastion.company.com
```
