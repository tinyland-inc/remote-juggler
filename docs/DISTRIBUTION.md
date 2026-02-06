# RemoteJuggler Distribution Guide

This guide is for **packagers and maintainers** who want to distribute RemoteJuggler through various channels.

For **user installation instructions**, see the [Installation Guide](getting-started/installation.md).

---

## Distribution Channels

### Primary Channels

| Channel | Type | Status |
|---------|------|--------|
| **GitLab Releases** | Source of truth | Primary |
| **Homebrew Tap** | macOS/Linux package manager | Active |
| **AUR** | Arch User Repository | Active |
| **Flathub** | Linux universal packages | Active |

### Package Registry URLs

| Platform | Registry |
|----------|----------|
| GitLab | `https://gitlab.com/tinyland/remote-juggler/-/releases` |
| Homebrew | `tinyland/tools/remote-juggler` |
| AUR | `remote-juggler` |
| Flatpak | `dev.tinyland.RemoteJuggler` |
| Nix | `gitlab:tinyland/remote-juggler` |

---

## Release Artifacts

Each release includes the following artifacts:

| File | Description |
|------|-------------|
| `remote-juggler-X.Y.Z-linux-amd64.tar.gz` | Linux x86_64 binary |
| `remote-juggler-X.Y.Z-linux-arm64.tar.gz` | Linux ARM64 binary |
| `remote-juggler-X.Y.Z-darwin-amd64.tar.gz` | macOS Intel binary |
| `remote-juggler-X.Y.Z-darwin-arm64.tar.gz` | macOS Apple Silicon binary |
| `RemoteJuggler-X.Y.Z.dmg` | macOS installer (signed, notarized) |
| `remote-juggler_X.Y.Z_amd64.deb` | Debian/Ubuntu package |
| `remote-juggler-X.Y.Z-1.x86_64.rpm` | Fedora/RHEL package |
| `remote-juggler-X.Y.Z-1-x86_64.pkg.tar.zst` | Arch Linux package |
| `RemoteJuggler-x86_64.AppImage` | Linux AppImage |
| `SHA256SUMS.txt` | Checksums for all files |
| `SHA256SUMS.txt.asc` | GPG signature |

---

## CI/CD Pipeline

Releases are automated via GitLab CI and triggered by version tags.

### Trigger Rules

```yaml
# Triggered by tags matching v*
release:
  stage: release
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
```

### Pipeline Stages

1. **Build** - Compile for all platforms (linux-amd64, linux-arm64, darwin-amd64, darwin-arm64)
2. **Test** - Run unit and integration tests
3. **Package** - Create distribution packages (.deb, .rpm, .pkg.tar.zst, .dmg, AppImage)
4. **Sign** - Code sign macOS binaries with Developer ID
5. **Notarize** - Submit to Apple for notarization
6. **Release** - Upload to GitLab Package Registry
7. **Publish** - Update downstream package managers (Homebrew tap, AUR)

### Required CI Variables

| Variable | Description | Protected |
|----------|-------------|-----------|
| `APPLE_DEVELOPER_ID` | Apple Developer ID for signing | Yes |
| `APPLE_NOTARIZATION_CREDS` | App-specific password for notarization | Yes |
| `GPG_SIGNING_KEY` | GPG key for checksum signing | Yes |
| `HOMEBREW_TAP_TOKEN` | Token for Homebrew tap repo | Yes |
| `AUR_SSH_KEY` | SSH key for AUR pushes | Yes |

---

## Code Signing

### macOS

All macOS binaries are signed with:
- **Developer ID Application** certificate
- **Hardened Runtime** enabled
- **Notarized** by Apple

Verify signature:
```bash
codesign -dv --verbose=4 /usr/local/bin/remote-juggler
spctl -a -vvv -t install RemoteJuggler.app
```

### GPG

Release checksums are signed with GPG key:
- **Key ID**: `ABC123DEF456` (replace with actual)
- **Fingerprint**: `XXXX XXXX XXXX XXXX XXXX XXXX XXXX XXXX XXXX XXXX`

Import key:
```bash
curl -fsSL https://gitlab.com/tinyland/remote-juggler/-/raw/main/keys/release-signing.asc | gpg --import
```

---

## Build Dependencies

For packagers building from source:

| Dependency | Version | Purpose |
|------------|---------|---------|
| Chapel | 2.6+ | Main CLI compiler |
| Rust | 1.75+ | GTK GUI (optional) |
| Go | 1.21+ | Linux tray app (optional) |
| Swift | 5.9+ | macOS tray app (optional) |
| TPM2-TSS | 4.0+ | TPM support (Linux, optional) |

### macOS Framework Dependencies

macOS builds link against system frameworks:
```makefile
CHPL_LDFLAGS = --ldflags="-framework Security -framework CoreFoundation"
```

### Linux Shared Library Dependencies

```bash
# Runtime dependencies
libgcc_s.so.1
libc.so.6
libpthread.so.0
```

---

## Packaging Guidelines

### Homebrew Formula

```ruby
class RemoteJuggler < Formula
  desc "Agent-first git identity management utility"
  homepage "https://gitlab.com/tinyland/remote-juggler"
  url "https://gitlab.com/tinyland/remote-juggler/-/archive/vX.Y.Z/remote-juggler-vX.Y.Z.tar.gz"
  sha256 "CHECKSUM"
  license "Zlib"

  depends_on "chapel" => :build

  def install
    system "just", "release"
    bin.install "target/release/remote-juggler"
    # Install completions
    bash_completion.install "completions/remote-juggler.bash"
    zsh_completion.install "completions/_remote-juggler"
    fish_completion.install "completions/remote-juggler.fish"
  end
end
```

### AUR PKGBUILD

```bash
pkgname=remote-juggler
pkgver=X.Y.Z
pkgrel=1
pkgdesc="Agent-first git identity management utility"
arch=('x86_64')
url="https://gitlab.com/tinyland/remote-juggler"
license=('Zlib')
depends=('glibc')
makedepends=('chapel')
source=("$pkgname-$pkgver.tar.gz::https://gitlab.com/tinyland/remote-juggler/-/archive/v$pkgver/remote-juggler-v$pkgver.tar.gz")
sha256sums=('CHECKSUM')

build() {
  cd "$srcdir/$pkgname-v$pkgver"
  just release
}

package() {
  cd "$srcdir/$pkgname-v$pkgver"
  install -Dm755 target/release/remote-juggler "$pkgdir/usr/bin/remote-juggler"
  install -Dm644 completions/remote-juggler.bash "$pkgdir/usr/share/bash-completion/completions/remote-juggler"
  install -Dm644 completions/_remote-juggler "$pkgdir/usr/share/zsh/site-functions/_remote-juggler"
  install -Dm644 completions/remote-juggler.fish "$pkgdir/usr/share/fish/vendor_completions.d/remote-juggler.fish"
}
```

### Flatpak Manifest

```yaml
app-id: dev.tinyland.RemoteJuggler
runtime: org.freedesktop.Platform
runtime-version: '23.08'
sdk: org.freedesktop.Sdk
command: remote-juggler
finish-args:
  - --filesystem=~/.ssh:ro
  - --filesystem=~/.config/remote-juggler:rw
  - --filesystem=~/.gitconfig:ro
modules:
  - name: remote-juggler
    buildsystem: simple
    build-commands:
      - just release
      - install -Dm755 target/release/remote-juggler /app/bin/remote-juggler
    sources:
      - type: archive
        url: https://gitlab.com/tinyland/remote-juggler/-/archive/vX.Y.Z/remote-juggler-vX.Y.Z.tar.gz
        sha256: CHECKSUM
```

---

## Verification Script

Use the provided script to verify downloads:

```bash
./scripts/verify-release.sh remote-juggler-X.Y.Z-linux-amd64.tar.gz
```

Or manually:

```bash
# 1. Import GPG key
curl -fsSL https://gitlab.com/tinyland/remote-juggler/-/raw/main/keys/release-signing.asc | gpg --import

# 2. Download checksums
curl -LO https://gitlab.com/.../SHA256SUMS.txt
curl -LO https://gitlab.com/.../SHA256SUMS.txt.asc

# 3. Verify signature
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt

# 4. Verify checksum
sha256sum -c SHA256SUMS.txt --ignore-missing
```

---

## License

- **Source code**: Zlib license (free and open source)
- **Prebuilt binaries**: Free for personal use, donations appreciated

See [LICENSE](../LICENSE) for full terms.
