# GPG Signing

Configure GPG commit and tag signing per identity.

## Overview

GPG signing provides cryptographic verification of commits and tags. RemoteJuggler manages per-identity GPG keys.

## Key Generation

### Create GPG Key

```bash
gpg --full-generate-key
```

Choose:
- Key type: RSA and RSA (default)
- Key size: 4096
- Expiration: 1 year recommended
- Real name: Your name for this identity
- Email: Must match identity email

### Example for Work Identity

```bash
gpg --full-generate-key
# Select RSA and RSA
# 4096 bits
# 1y expiration
# Real name: Work User
# Email: work@company.com
```

## Listing Keys

### All Secret Keys

```bash
gpg --list-secret-keys --keyid-format=long
```

Output:
```
/Users/user/.gnupg/pubring.kbx
------------------------------
sec   rsa4096/ABC123DEF456 2024-01-15 [SC] [expires: 2025-01-15]
      ABCDEF1234567890ABCDEF1234567890ABC123DE
uid                 [ultimate] Work User <work@company.com>
ssb   rsa4096/GHI789JKL012 2024-01-15 [E] [expires: 2025-01-15]
```

### RemoteJuggler Key List

```bash
remote-juggler gpg status
```

Shows:
- Available GPG keys
- Per-identity GPG configuration
- Signing preferences

## Configuration

### Configure Identity GPG

Add to identity configuration:

```json
{
  "identities": {
    "work": {
      "gpg": {
        "keyId": "ABC123DEF456",
        "signCommits": true,
        "signTags": true,
        "autoSignoff": false
      }
    }
  }
}
```

### Auto-Detect Key by Email

```bash
remote-juggler gpg configure work
```

Searches for GPG key matching the identity's email address.

## Provider Registration

GPG keys must be registered with the provider for verification.

### GitLab

1. Export public key:
   ```bash
   gpg --armor --export ABC123DEF456
   ```

2. Go to GitLab > Settings > GPG Keys

3. Paste the public key

### GitHub

1. Export public key:
   ```bash
   gpg --armor --export ABC123DEF456
   ```

2. Go to GitHub > Settings > SSH and GPG keys

3. Click "New GPG key" and paste

### Verification URL

```bash
remote-juggler gpg verify
```

Shows registration status and direct links to settings pages.

## Git Configuration

### Manual Setup

```bash
# Set signing key
git config --global user.signingkey ABC123DEF456

# Enable commit signing
git config --global commit.gpgsign true

# Enable tag signing
git config --global tag.gpgsign true
```

### RemoteJuggler Automatic Setup

When switching identities with GPG configured:

```bash
remote-juggler switch work
```

Automatically sets:
- `user.signingkey`
- `commit.gpgsign`
- `tag.gpgsign` (if configured)

## Signing Operations

### Sign Commits

With `commit.gpgsign = true`:

```bash
git commit -m "Signed commit"
```

Manual signing:

```bash
git commit -S -m "Explicitly signed commit"
```

### Sign Tags

With `tag.gpgsign = true`:

```bash
git tag v1.0.0
```

Manual signing:

```bash
git tag -s v1.0.0 -m "Signed release"
```

### Verify Signatures

```bash
# Verify commit
git log --show-signature -1

# Verify tag
git tag -v v1.0.0
```

## GPG Agent

### Configure Agent

`~/.gnupg/gpg-agent.conf`:

```
default-cache-ttl 3600
max-cache-ttl 86400
pinentry-program /usr/local/bin/pinentry-mac
```

### Restart Agent

```bash
gpgconf --kill gpg-agent
gpgconf --launch gpg-agent
```

## Troubleshooting

### "secret key not available"

Key not found in GPG keyring:

```bash
# List available keys
gpg --list-secret-keys

# Import key if needed
gpg --import private-key.asc
```

### "failed to sign the data"

GPG agent issue:

```bash
# Test GPG signing
echo "test" | gpg --clearsign

# Restart agent
gpgconf --kill gpg-agent
```

### Pinentry Issues (macOS)

Install pinentry-mac:

```bash
brew install pinentry-mac
echo "pinentry-program $(which pinentry-mac)" >> ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent
```

### TTY Issues

Set GPG TTY:

```bash
# Add to ~/.bashrc or ~/.zshrc
export GPG_TTY=$(tty)
```

### Git Commit Hangs

GPG waiting for passphrase input:

```bash
# Use GUI pinentry
echo "pinentry-program /usr/local/bin/pinentry-mac" >> ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent
```

## Key Management

### Export Public Key

```bash
gpg --armor --export ABC123DEF456 > work-gpg-public.asc
```

### Export Private Key (Backup)

```bash
gpg --armor --export-secret-keys ABC123DEF456 > work-gpg-private.asc
```

Store securely (encrypted backup).

### Key Expiration

Extend key expiration:

```bash
gpg --edit-key ABC123DEF456
gpg> expire
# Set new expiration
gpg> save
```

Re-upload public key to providers after extension.

### Revoke Key

If key is compromised:

```bash
gpg --gen-revoke ABC123DEF456 > revoke.asc
gpg --import revoke.asc
```

Remove from provider settings.

## Multiple Keys Per Identity

Some setups require different keys for commits vs tags:

```json
{
  "gpg": {
    "keyId": "ABC123DEF456",
    "signCommits": true,
    "signTags": true,
    "tagKeyId": "XYZ789ABC123"
  }
}
```

Note: This requires custom git configuration beyond RemoteJuggler's standard setup.
