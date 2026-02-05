# pinentry-remotejuggler

Custom pinentry for RemoteJuggler that retrieves YubiKey PINs from TPM/SecureEnclave in "Trusted Workstation" mode.

## Overview

Standard `gpg-preset-passphrase` does NOT work with YubiKey PINs because the PIN is cached by the smartcard hardware, not by gpg-agent. This custom pinentry solves this by:

1. Intercepting PIN requests from gpg-agent via the Assuan protocol
2. Checking if the identity has "trusted workstation" mode enabled
3. Retrieving the PIN from TPM (Linux) or SecureEnclave (macOS) if configured
4. Falling back to the standard pinentry dialog if not

## Security Model

```
User provides PIN once ──► Encrypted with HSM key ──► Stored in HSM
                                                            │
                    PIN immediately cleared from memory ◄──┘

When signing needed:
  gpg-agent ──► pinentry-remotejuggler ──► HSM unseal ──► PIN to gpg
                                                            │
                                   PIN cleared after use ◄──┘
```

**Key Security Properties:**
- PIN never stored in application memory longer than necessary
- PIN encrypted before any persistence (sealed to TPM or SE key)
- Decryption happens within the HSM hardware
- PIN passed directly to gpg-agent, then cleared
- TPM-sealed PINs bound to platform boot state (PCR 7 by default)

## Installation

### Quick Install (Python only)

```bash
# Make executable
chmod +x pinentry-remotejuggler.py

# Create symlink
sudo ln -s /path/to/pinentry-remotejuggler.py /usr/local/bin/pinentry-remotejuggler

# Configure gpg-agent
echo "pinentry-program /usr/local/bin/pinentry-remotejuggler" >> ~/.gnupg/gpg-agent.conf

# Reload gpg-agent
gpgconf --kill gpg-agent
```

### Full Install (with HSM library)

```bash
# Build and install
make
sudo make install

# This installs:
#   /usr/local/lib/libhsm_remotejuggler.{so,dylib}
#   /usr/local/bin/pinentry-remotejuggler
```

### Platform-Specific Requirements

**Linux (TPM 2.0):**
```bash
# Install TPM2 libraries (Debian/Ubuntu)
sudo apt install libtss2-dev tpm2-tools

# Install TPM2 libraries (Fedora/RHEL)
sudo dnf install tpm2-tss-devel tpm2-tools

# Ensure user has TPM access
sudo usermod -a -G tss $USER
```

**macOS (Secure Enclave):**
- Requires macOS 10.12.1+ with T2 or Apple Silicon chip
- No additional libraries needed (uses Security.framework)

## Configuration

### Enable Trusted Workstation Mode

Edit `~/.config/remote-juggler/config.json`:

```json
{
  "identities": {
    "gitlab-personal": {
      "gpg": {
        "keyId": "8547785CA25F0AA8",
        "hardwareKey": true,
        "signCommits": true,
        "securityMode": "trusted_workstation",
        "pinStorageMethod": "tpm"
      }
    }
  }
}
```

**securityMode options:**
- `maximum_security` - PIN required for every operation (default YubiKey behavior)
- `developer_workflow` - PIN cached for session (default)
- `trusted_workstation` - PIN stored in TPM/SecureEnclave

**pinStorageMethod options:**
- `tpm` - Linux TPM 2.0
- `secure_enclave` - macOS Secure Enclave
- `keychain` - System keychain (fallback, less secure)
- `""` (empty) - Auto-detect

### Store PIN in HSM

```bash
# Using remote-juggler CLI (when implemented)
remote-juggler seal-pin gitlab-personal

# The command will prompt for your YubiKey PIN
# and store it encrypted in the HSM
```

## How It Works

### Assuan Protocol

pinentry uses a simple line-based protocol:

```
< OK Pleased to meet you
> SETDESC Please enter the PIN for key 8547785CA25F0AA8
< OK
> SETPROMPT PIN:
< OK
> GETPIN
< D 123456
< OK
> BYE
< OK closing connection
```

### Key Detection

The pinentry extracts the GPG key ID from the `SETDESC` message, then:
1. Looks up the identity in RemoteJuggler's config
2. Checks if `securityMode: "trusted_workstation"`
3. If yes, calls `remote-juggler unseal-pin <identity>` to get PIN from HSM
4. If no or if unseal fails, delegates to system pinentry

### Fallback Behavior

When HSM retrieval fails or is not configured, the pinentry automatically falls back to the system pinentry. Detection order:

1. `/usr/local/bin/pinentry-mac` (macOS Homebrew)
2. `/opt/homebrew/bin/pinentry-mac` (macOS Apple Silicon)
3. `/usr/bin/pinentry-gnome3` (GNOME)
4. `/usr/bin/pinentry-qt` (KDE)
5. `/usr/bin/pinentry-gtk-2` (GTK2)
6. `/usr/bin/pinentry-curses` (Terminal)
7. `/usr/bin/pinentry` (Generic)

## Environment Variables

| Variable | Description |
|----------|-------------|
| `PINENTRY_REMOTEJUGGLER_DEBUG` | Set to `1` to enable debug logging to stderr |
| `PINENTRY_REMOTEJUGGLER_FALLBACK` | Override the fallback pinentry path |
| `REMOTE_JUGGLER_BIN` | Override the remote-juggler binary path |

## Debugging

Enable debug output:

```bash
export PINENTRY_REMOTEJUGGLER_DEBUG=1
gpg --clearsign somefile.txt 2>&1 | tee debug.log
```

Debug output goes to stderr and includes:
- Protocol commands received/sent
- Identity detection
- HSM operations
- Fallback behavior

## Files

| File | Description |
|------|-------------|
| `pinentry-remotejuggler.py` | Python implementation (primary) |
| `hsm.h` | C header for HSM abstraction |
| `hsm_darwin.c` | macOS Secure Enclave implementation |
| `hsm_linux.c` | Linux TPM 2.0 implementation |
| `hsm_stub.c` | Fallback stub (for testing/dev) |
| `Makefile` | Build system |
| `test_hsm.c` | Test program for HSM library |

## Threat Model

| Threat | Mitigation |
|--------|------------|
| Malware reads PIN from memory | PIN only in HSM memory during decrypt |
| Stolen laptop with disk access | PIN encrypted with HSM key, cannot decrypt without hardware |
| Evil maid attack | TPM PCR binding detects boot tampering |
| Compromised RemoteJuggler binary | HSM key requires user authentication |
| gpg-agent memory dump | Standard gpg-agent risk, not increased |

## Limitations

- **TPM boot state sensitivity**: If you update your bootloader, kernel, or Secure Boot certificates, TPM-sealed PINs become inaccessible. You'll need to re-seal them.
- **No Touch ID in CLI**: Secure Enclave operations from CLI cannot trigger Touch ID prompt. SE encryption is used without biometric gate.
- **YubiKey PIN policy**: The YubiKey hardware still enforces its own PIN caching policy. This solution provides the PIN automatically but cannot disable the hardware's security requirements.

## License

MIT License - See LICENSE file in the RemoteJuggler repository.
