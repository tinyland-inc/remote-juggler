# Trusted Workstation Setup Guide

This guide covers building and testing RemoteJuggler's Trusted Workstation mode
with real HSM hardware (TPM 2.0 on Linux, Secure Enclave on macOS).

## Test Machines

| Machine | OS | HSM Hardware | Purpose |
|---------|-----|--------------|---------|
| yoga | Rocky Linux 10.1 | TPM 2.0 | Primary development, TPM testing |
| honey | Linux (server) | TPM 2.0 | Server TPM testing |
| petting-zoo-mini | macOS | Secure Enclave | macOS/SE testing |

---

## Yoga / Honey (Linux TPM Setup)

### Prerequisites

```bash
# Rocky Linux / RHEL / Fedora
sudo dnf install -y \
    tpm2-tss \
    tpm2-tss-devel \
    tpm2-abrmd \
    tpm2-tools \
    make \
    gcc

# Ubuntu / Debian
sudo apt install -y \
    libtss2-dev \
    tpm2-abrmd \
    tpm2-tools \
    build-essential
```

### Enable TPM

```bash
# Load TPM kernel module (try crb first, then tis)
sudo modprobe tpm_crb || sudo modprobe tpm_tis

# Verify TPM device exists
ls -la /dev/tpm*
# Should show: /dev/tpm0 and/or /dev/tpmrm0

# Start TPM resource manager
sudo systemctl enable --now tpm2-abrmd

# Verify TPM is accessible
tpm2_getcap properties-fixed | head -20

# Add user to tss group for non-root access
sudo usermod -aG tss $USER
# LOG OUT AND BACK IN for group to take effect
```

### Build with TPM Support

```bash
cd ~/git/RemoteJuggler

# Verify TPM libraries are detected
pkg-config --exists tss2-esys && echo "TPM2-TSS: OK" || echo "TPM2-TSS: MISSING"

# Build HSM library with real TPM backend
cd pinentry
make clean
make
# Should say: "Building with hsm_linux.c" (not hsm_stub.c)

# Run TPM tests
make test
# All 70 tests should pass with real TPM

# Build main Chapel binary
cd ..
make clean
make release

# Verify HSM is detected
./target/release/remote_juggler pin status
# Should show: "HSM Backend: TPM 2.0"
```

### Install Locally

```bash
# Install to ~/.local/bin (user-wide)
make install

# Or install system-wide
sudo make install PREFIX=/usr/local

# Verify installation
which remote-juggler
remote-juggler --version
```

---

## Petting-Zoo-Mini (macOS Secure Enclave Setup)

### Prerequisites

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Install Chapel (via Homebrew)
brew install chapel

# Verify Secure Enclave (requires T2 chip or Apple Silicon)
system_profiler SPiBridgeDataType 2>/dev/null | grep -i "Model Name" || \
    sysctl -n machdep.cpu.brand_string | grep -i "Apple"
```

### Build with Secure Enclave Support

```bash
cd ~/git/RemoteJuggler

# Build HSM library with Secure Enclave backend
cd pinentry
make clean
make
# Should link with: -framework Security -framework CoreFoundation

# Run Secure Enclave tests
make test
# Tests will use SE for real encryption

# Build main Chapel binary
cd ..
make clean
make release

# Verify SE is detected
./target/release/remote_juggler pin status
# Should show: "HSM Backend: Secure Enclave"
```

### Install Locally

```bash
# Install to ~/.local/bin
make install

# Or via Homebrew (if tap exists)
# brew install tinyland/tap/remote-juggler
```

---

## Testing Trusted Workstation Mode

### Basic Flow

```bash
# 1. Check HSM status
remote-juggler pin status

# 2. Store a PIN for an identity
remote-juggler pin store personal
# Enter PIN when prompted (or use --pin for non-interactive)

# 3. Verify PIN is stored
remote-juggler pin status
# Should show "personal: PIN stored"

# 4. Set security mode
remote-juggler security-mode trusted_workstation

# 5. Enable Trusted Workstation for identity
remote-juggler trusted-workstation enable --identity personal

# 6. Verify setup
remote-juggler trusted-workstation verify --identity personal
```

### Test PIN Retrieval

```bash
# The PIN should be retrievable from HSM
remote-juggler debug hsm

# For gpg-agent integration, configure pinentry:
# ~/.gnupg/gpg-agent.conf:
#   pinentry-program /path/to/pinentry-remotejuggler

# Reload gpg-agent
gpgconf --kill gpg-agent

# Test GPG signing (should auto-retrieve PIN from HSM)
echo "test" | gpg --clearsign
```

### Run Integration Tests

```bash
# Full E2E test suite
./test/integration/test_trusted_workstation.sh

# With TAP output for CI
./test/integration/test_trusted_workstation.sh --tap

# Skip YubiKey tests if ykman not installed
./test/integration/test_trusted_workstation.sh --skip-yubikey
```

---

## Troubleshooting

### TPM Not Found (Linux)

```bash
# Check if TPM hardware exists
sudo dmesg | grep -i tpm

# Try loading module manually
sudo modprobe tpm_crb
sudo modprobe tpm_tis

# Check BIOS/UEFI - TPM may be disabled
# Reboot and enable TPM in firmware settings
```

### TPM Access Denied

```bash
# Check device permissions
ls -la /dev/tpm*

# Add user to tss group
sudo usermod -aG tss $USER
newgrp tss  # or log out/in

# Check if tpm2-abrmd is running
systemctl status tpm2-abrmd
```

### Secure Enclave Not Available (macOS)

```bash
# SE requires T2 chip (2018+ Intel Macs) or Apple Silicon
# Check for SE capability:
system_profiler SPSecureElementDataType

# If no SE, falls back to Keychain (software encryption)
```

### PCR Mismatch Error

```bash
# This means boot state changed since PIN was sealed
# (e.g., BIOS update, Secure Boot config change)

# Re-store the PIN to seal with new PCR values:
remote-juggler pin clear personal
remote-juggler pin store personal
```

---

## Security Considerations

### TPM PCR Binding

By default, PINs are sealed to PCR 7 (Secure Boot state). This means:
- PIN cannot be retrieved if boot configuration changes
- Protects against offline attacks and boot tampering

To customize PCR binding:
```bash
# Bind to PCRs 0, 7, and 14
remote-juggler config set hsm.pcr_mask 0x4081
```

### Secure Enclave Biometric

On macOS, you can require Touch ID for PIN retrieval:
```bash
remote-juggler config set hsm.require_biometric true
```

### Clearing All PINs

Emergency clear all stored PINs:
```bash
remote-juggler pin clear --all
```
