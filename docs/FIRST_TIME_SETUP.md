# First-Time Setup Guide

This guide walks you through setting up RemoteJuggler for the first time.

---

## Quick Start

```bash
# Run the interactive setup wizard
remote-juggler setup

# Or auto-detect everything non-interactively
remote-juggler setup --auto
```

---

## What the Setup Wizard Does

The setup wizard automatically:

1. **Detects SSH hosts** from `~/.ssh/config`
   - Finds git provider hosts (GitHub, GitLab, Bitbucket)
   - Extracts identity files and user information
   - Creates identity configurations for each host

2. **Discovers GPG keys** from your keyring
   - Lists available signing keys
   - Matches keys to identities by email patterns
   - Configures GPG signing where applicable

3. **Checks for hardware security modules**
   - **Linux**: TPM 2.0 (`/dev/tpm0` or `/dev/tpmrm0`)
   - **macOS**: Secure Enclave (T1/T2/Apple Silicon)
   - **YubiKey**: Detects connected YubiKeys via `ykman`

4. **Generates configuration** at `~/.config/remote-juggler/config.json`

---

## Prerequisites

### SSH Configuration

Ensure your `~/.ssh/config` has host aliases for your git providers:

```ssh-config
# Personal GitLab
Host gitlab-personal
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal

# Work GitLab
Host gitlab-work
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work

# GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_github
```

### GPG Keys (Optional)

For commit signing, ensure GPG keys are imported:

```bash
# List existing keys
gpg --list-secret-keys --keyid-format=long

# If no keys, generate one
gpg --full-generate-key
```

### Hardware Security (Optional)

For Trusted Workstation mode:

**Linux (TPM 2.0)**:
```bash
# Install TPM tools
sudo dnf install tpm2-tss tpm2-tools tpm2-abrmd  # RHEL/Fedora
sudo apt install libtss2-dev tpm2-tools tpm2-abrmd  # Debian/Ubuntu

# Verify TPM is accessible
tpm2_getcap properties-fixed
```

**macOS (Secure Enclave)**:
- Requires Mac with T1/T2 chip or Apple Silicon
- No additional setup needed

---

## Setup Modes

### Interactive Mode (Default)

```bash
remote-juggler setup
```

Walks through each step with prompts, allowing you to:
- Select which SSH hosts to import
- Choose GPG key associations
- Configure HSM options

### Auto Mode

```bash
remote-juggler setup --auto
```

Automatically detects and configures everything without prompts. Best for:
- Scripted installations
- CI/CD environments
- When defaults are acceptable

### Import SSH Only

```bash
remote-juggler setup --import-ssh
```

Only imports SSH hosts, skipping GPG and HSM detection.

### Import GPG Only

```bash
remote-juggler setup --import-gpg
```

Only detects GPG keys to add to existing identities.

### Status Check

```bash
remote-juggler setup --status
```

Shows current setup state without making changes.

---

## Setup Output

After running setup, you'll see a summary:

```
╔══════════════════════════════════════════════════════════════╗
║              RemoteJuggler First-Time Setup                  ║
╚══════════════════════════════════════════════════════════════╝

Step 1: Detecting SSH hosts from ~/.ssh/config...
  Found 3 SSH host(s):
    [x] gitlab-personal (gitlab) → gitlab.com
    [x] gitlab-work (gitlab) → gitlab.com
    [x] github.com (github) → github.com

Step 2: Detecting GPG signing keys...
  Found 2 GPG key(s):
    [x] ABC123DEF456 <jess@sulliwood.org> → gitlab-personal
    [ ] DEF789GHI012 <jsullivan2@bates.edu>

Step 3: Detecting hardware security modules...
  ✓ Found: TPM 2.0 hardware module
  Trusted Workstation mode is available!

Step 4: Generating configuration...
  ✓ Configuration written to: ~/.config/remote-juggler/config.json

════════════════════════════════════════════════════════════════
                        Setup Complete
════════════════════════════════════════════════════════════════

  Identities created: 3
  GPG keys associated: 1
  HSM detected: Yes (tpm)

Next steps:
  1. Review the config at: ~/.config/remote-juggler/config.json
  2. Add email addresses to identities
  3. Run 'remote-juggler list' to see your identities
  4. Run 'remote-juggler switch <identity>' to switch
  5. Run 'remote-juggler pin store <identity>' for passwordless signing
```

---

## Post-Setup Configuration

### Add Email Addresses

Edit `~/.config/remote-juggler/config.json` to add email addresses:

```json
{
  "identities": {
    "gitlab-personal": {
      "provider": "gitlab",
      "host": "gitlab-personal",
      "hostname": "gitlab.com",
      "user": "git",
      "identityFile": "~/.ssh/id_ed25519_personal",
      "email": "jess@sulliwood.org",
      "name": "Jess Sullivan"
    }
  }
}
```

### Associate GPG Keys

Add GPG configuration to identities:

```json
{
  "identities": {
    "gitlab-personal": {
      "gpg": {
        "keyId": "ABC123DEF456",
        "format": "gpg",
        "hardwareKey": true,
        "touchPolicy": "cached"
      }
    }
  }
}
```

### Configure Trusted Workstation Mode

If HSM was detected, you can enable passwordless signing:

```bash
# Store YubiKey PIN in TPM/Secure Enclave
remote-juggler pin store gitlab-personal

# Enable Trusted Workstation mode
remote-juggler security-mode trusted_workstation

# Verify setup
remote-juggler pin status
```

---

## Verify Setup

```bash
# List configured identities
remote-juggler list

# Check current status
remote-juggler status

# Validate an identity
remote-juggler validate personal

# Test switching
remote-juggler switch gitlab-personal
```

---

## Common Issues

### No SSH Hosts Detected

**Problem**: Setup says "No SSH hosts found"

**Solution**: Create SSH host entries in `~/.ssh/config`:
```bash
# Example: Add a GitLab personal host
cat >> ~/.ssh/config << 'EOF'

Host gitlab-personal
    HostName gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_personal
EOF
```

### GPG Keys Not Detected

**Problem**: Setup doesn't find GPG keys

**Solution**: Verify GPG is installed and keys are present:
```bash
# Check GPG installation
gpg --version

# List secret keys
gpg --list-secret-keys

# If empty, generate a key
gpg --full-generate-key
```

### HSM Not Detected (Linux)

**Problem**: TPM 2.0 not detected on Linux

**Solutions**:
1. Check if TPM device exists:
   ```bash
   ls -la /dev/tpm*
   ```

2. Load TPM kernel module:
   ```bash
   sudo modprobe tpm_crb || sudo modprobe tpm_tis
   ```

3. Check BIOS/UEFI settings - TPM may be disabled

4. Add user to `tss` group:
   ```bash
   sudo usermod -aG tss $USER
   # Log out and back in
   ```

### HSM Not Detected (macOS)

**Problem**: Secure Enclave not detected

**Requirement**: Secure Enclave requires:
- Mac with T1 chip (2016+)
- Mac with T2 chip (2018+)
- Mac with Apple Silicon (M1/M2/M3)

Older Macs without these chips cannot use Secure Enclave.

### Configuration Already Exists

**Problem**: Setup warns about existing configuration

**Solution**: Use `--force` to overwrite:
```bash
remote-juggler setup --force
```

Or backup and regenerate:
```bash
mv ~/.config/remote-juggler/config.json ~/.config/remote-juggler/config.json.bak
remote-juggler setup
```

---

## MCP Integration

For AI agent integration, use the `juggler_setup` MCP tool:

```json
{
  "name": "juggler_setup",
  "arguments": {
    "mode": "auto"
  }
}
```

Available modes:
- `interactive` - Full wizard (not recommended for agents)
- `auto` - Non-interactive detection and configuration
- `import_ssh` - SSH hosts only
- `import_gpg` - GPG keys only
- `status` - Read-only status check

---

## Next Steps

- [Trusted Workstation Setup](./TRUSTED_WORKSTATION_SETUP.md) - HSM configuration
- [Configuration Reference](../reference/config-schema.md) - Full config.json schema
- [CLI Reference](../cli/commands.md) - All commands and options
