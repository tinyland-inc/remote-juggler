# RemoteJuggler Distribution Strategy

**Last Updated**: 2026-01-17

---

## Executive Summary

This document outlines the distribution strategy for RemoteJuggler, a Chapel-based CLI tool for git identity management. The strategy balances open-source availability with sustainable revenue through paid binaries.

### Key Findings

| Distribution Channel | Viable? | Notes |
|---------------------|---------|-------|
| Mac App Store | **No** | Sandbox blocks SSH/git config access |
| Notarized Direct Sales | **Yes** | Full CLI functionality, recommended |
| Homebrew Tap | **Yes** | Free distribution, community building |
| GitHub Releases | **Yes** | Primary download source |

---

## License Structure

### Dual License Model

RemoteJuggler uses a **dual-license** approach:

| License | Applies To | Cost |
|---------|------------|------|
| **zlib** | Source code | Free |
| **Commercial** | Prebuilt binaries | Donation ($3-10) |

### Why zlib?

The zlib license is ideal for this model:

1. **No binary attribution required** - Simplifies distribution
2. **Modification marking required** - Protects brand (official vs modified)
3. **Maximum permissiveness** - Commercial integration allowed
4. **Simpler than MIT/BSD** - No attribution in product docs needed

### Legal Clarity

- Anyone MAY compile from source for free
- Prebuilt binaries are offered as convenience + support donation
- Commercial use encouraged to contribute (social/moral obligation, not legal)
- Package maintainer program (Section 5) provides community path

---

## Mac App Store: Not Viable

### Why CLI Tools Can't Use the App Store

According to Apple Developer Forums and documentation:

1. **Sandbox Requirement**: All App Store apps must run sandboxed
2. **CLI Execution**: Sandboxed CLI tools cannot be invoked from Terminal
3. **File Access**: Cannot access paths provided as command-line arguments
4. **Config Modifications**: Cannot modify `~/.ssh/config` or `~/.gitconfig`

### RemoteJuggler-Specific Blockers

| Requirement | App Store Compatible? |
|-------------|----------------------|
| Read/write ~/.ssh/config | ❌ Blocked by sandbox |
| Read/write ~/.gitconfig | ❌ Blocked by sandbox |
| Keychain access | ⚠️ Limited to app-specific |
| Terminal execution | ❌ No sandbox inheritance |
| MCP server mode | ❌ STDIO not supported |

### Menu Bar Wrapper Option

A **menu bar companion app** could be distributed on the App Store:

```swift
@main
struct RemoteJugglerApp: App {
    var body: some Scene {
        MenuBarExtra("RemoteJuggler", systemImage: "person.2.badge.gearshape") {
            // Status display, quick switching
        }
    }
}
```

**Limitations**:
- Would require separate CLI distribution anyway
- Adds maintenance burden for minimal benefit
- Users expect CLI tools via Homebrew, not App Store

**Recommendation**: Skip App Store entirely. Focus on direct distribution.

---

## Recommended Distribution Channels

### 1. GitHub Releases (Primary)

**Artifacts per release:**
```
remote-juggler-2.0.0-darwin-arm64.tar.gz
remote-juggler-2.0.0-darwin-amd64.tar.gz
remote-juggler-2.0.0-linux-amd64.tar.gz
remote-juggler-2.0.0-linux-arm64.tar.gz
SHA256SUMS.txt
SHA256SUMS.txt.asc
```

**Verification workflow for users:**
```bash
# Download checksum file and signature from GitLab releases
curl -LO https://gitlab.com/tinyland/projects/remote-juggler/-/releases/.../SHA256SUMS.txt
curl -LO https://gitlab.com/tinyland/projects/remote-juggler/-/releases/.../SHA256SUMS.txt.asc

# Verify GPG signature
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt

# Verify checksum
sha256sum -c SHA256SUMS.txt --ignore-missing
```

### 2. Homebrew Tap (Free Distribution)

```ruby
# Formula: remote-juggler.rb
class RemoteJuggler < Formula
  desc "Backend-agnostic git identity management with MCP support"
  homepage "https://gitlab.com/tinyland/projects/remote-juggler"
  url "https://gitlab.com/tinyland/projects/remote-juggler/-/archive/v2.0.0/remote-juggler-v2.0.0.tar.gz"
  sha256 "..."
  license "Zlib"

  depends_on "chapel" => :build

  def install
    system "just", "release"
    bin.install "remote-juggler"
    # Install shell completions
    bash_completion.install "completions/remote-juggler.bash"
    zsh_completion.install "completions/_remote-juggler"
    fish_completion.install "completions/remote-juggler.fish"
  end
end
```

**Installation:**
```bash
brew tap tinyland/tools
brew install remote-juggler
```

### 3. Direct Sales (Paid Binaries)

**Platform options:**

| Platform | Fees | VAT Handling | Recommended |
|----------|------|--------------|-------------|
| Gumroad | 10% + payment | Included | ✅ Simple |
| Paddle | ~5% + payment | Included | ✅ Best rates |
| Ko-fi | 5% (Gold) | Manual | Coffee-style |
| GitHub Sponsors | 0% | Manual | Recurring |

**Recommended: Gumroad or Paddle**

- One-time purchase ($5-10)
- Handles VAT/GST automatically
- License key optional (trust-based model)
- Instant download after payment

### 4. Package Managers

| Platform | Format | Notes |
|----------|--------|-------|
| Homebrew | Formula | Primary macOS/Linux |
| MacPorts | Portfile | Alternative macOS |
| AUR | PKGBUILD | Arch Linux |
| Nix | Derivation | NixOS/Nix users |

---

## Code Signing and Notarization

### macOS (Required for Gatekeeper)

**Prerequisites:**
- Apple Developer Program ($99/year)
- Developer ID Application certificate
- Developer ID Installer certificate (for PKG)

**Signing workflow:**
```bash
# Sign the binary
codesign --sign "Developer ID Application: Your Name" \
  --options runtime \
  --timestamp \
  remote-juggler

# Create DMG
hdiutil create -volname "RemoteJuggler" \
  -srcfolder build/ \
  -ov RemoteJuggler.dmg

# Notarize
xcrun notarytool submit RemoteJuggler.dmg \
  --keychain-profile "RJ-notary" \
  --wait

# Staple ticket
xcrun stapler staple RemoteJuggler.dmg

# Verify
spctl --assess --type open \
  --context context:primary-signature \
  RemoteJuggler.dmg
```

### Windows (Optional but Recommended)

**Options:**
- EV Code Signing Certificate (~$400/year) - Immediate trust
- Standard Certificate (~$200/year) - Builds reputation over time
- Self-signed - SmartScreen warnings, not recommended

### Linux

No signing required, but GPG signatures recommended for verification.

---

## Checksum and Signature Verification

### Generating Release Checksums

```bash
#!/bin/bash
# scripts/generate-checksums.sh

cd release/

# Generate SHA-256 checksums
sha256sum remote-juggler-* > SHA256SUMS.txt

# Sign with GPG
gpg --armor --detach-sign SHA256SUMS.txt

# Display for verification
cat SHA256SUMS.txt
echo ""
echo "Signature: SHA256SUMS.txt.asc"
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt
```

### GPG Key Management

**Key requirements:**
- RSA 4096-bit or Ed25519
- Published to keyservers (keys.openpgp.org)
- Fingerprint documented on website and GitHub

**Key details to document:**
```
GPG Key: B7D382A890EA8DA4
Fingerprint: XXXX XXXX XXXX XXXX XXXX  XXXX B7D3 82A8 90EA 8DA4
Key Server: keys.openpgp.org
```

---

## Installer Script

### Cross-Platform Install Script

```bash
#!/bin/bash
# install.sh - RemoteJuggler installer

set -e

VERSION="${RJ_VERSION:-latest}"
INSTALL_DIR="${RJ_INSTALL_DIR:-$HOME/.local/bin}"

# Detect platform
detect_platform() {
    local os arch

    case "$(uname -s)" in
        Darwin) os="darwin" ;;
        Linux)  os="linux" ;;
        *)      echo "Unsupported OS"; exit 1 ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)   arch="amd64" ;;
        arm64|aarch64)  arch="arm64" ;;
        *)              echo "Unsupported architecture"; exit 1 ;;
    esac

    echo "${os}-${arch}"
}

# Download and verify
download_and_verify() {
    local platform="$1"
    local url="https://gitlab.com/tinyland/projects/remote-juggler/-/releases/v${VERSION}/downloads"
    local binary="remote-juggler-${VERSION}-${platform}.tar.gz"

    echo "Downloading ${binary}..."
    curl -fsSL -o "$binary" "${url}/${binary}"
    curl -fsSL -o SHA256SUMS.txt "${url}/SHA256SUMS.txt"
    curl -fsSL -o SHA256SUMS.txt.asc "${url}/SHA256SUMS.txt.asc"

    echo "Verifying signature..."
    if command -v gpg >/dev/null 2>&1; then
        gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt 2>/dev/null || {
            echo "Warning: GPG signature verification failed or key not imported"
            echo "Import key: gpg --keyserver keys.openpgp.org --recv-keys B7D382A890EA8DA4"
        }
    fi

    echo "Verifying checksum..."
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c SHA256SUMS.txt --ignore-missing
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -c SHA256SUMS.txt --ignore-missing
    fi

    echo "$binary"
}

# Install binary
install_binary() {
    local archive="$1"

    mkdir -p "$INSTALL_DIR"
    tar -xzf "$archive" -C "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR/remote-juggler"

    echo "Installed to $INSTALL_DIR/remote-juggler"

    # Check PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo ""
        echo "Add to your PATH:"
        echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
    fi
}

# Main
main() {
    local platform binary

    platform=$(detect_platform)
    echo "Detected platform: $platform"

    local tmpdir=$(mktemp -d)
    cd "$tmpdir"

    binary=$(download_and_verify "$platform")
    install_binary "$binary"

    cd - >/dev/null
    rm -rf "$tmpdir"

    echo ""
    echo "Installation complete!"
    echo "Run 'remote-juggler --help' to get started."
}

main "$@"
```

**Usage:**
```bash
curl -fsSL https://gitlab.com/tinyland/projects/remote-juggler/-/raw/main/install.sh | bash
```

---

## CI/CD Integration

### GitHub Actions for Releases

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    strategy:
      matrix:
        include:
          - os: macos-latest
            platform: darwin-arm64
          - os: macos-13
            platform: darwin-amd64
          - os: ubuntu-latest
            platform: linux-amd64

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: just release

      - name: Sign (macOS)
        if: startsWith(matrix.platform, 'darwin')
        run: |
          codesign --sign "${{ secrets.APPLE_DEVELOPER_ID }}" \
            --options runtime --timestamp \
            remote-juggler

      - name: Package
        run: |
          tar -czvf remote-juggler-${{ github.ref_name }}-${{ matrix.platform }}.tar.gz \
            remote-juggler

      - uses: actions/upload-artifact@v4
        with:
          name: binary-${{ matrix.platform }}
          path: "*.tar.gz"

  release:
    needs: build
    runs-on: macos-latest

    steps:
      - uses: actions/download-artifact@v4

      - name: Generate checksums
        run: |
          cd binary-*
          sha256sum remote-juggler-* > ../SHA256SUMS.txt

      - name: Sign checksums
        run: |
          echo "${{ secrets.GPG_PRIVATE_KEY }}" | gpg --import
          gpg --armor --detach-sign SHA256SUMS.txt

      - name: Notarize (macOS)
        run: |
          for dmg in binary-darwin-*/*.tar.gz; do
            xcrun notarytool submit "$dmg" \
              --apple-id "${{ secrets.APPLE_ID }}" \
              --password "${{ secrets.APPLE_APP_PASSWORD }}" \
              --team-id "${{ secrets.APPLE_TEAM_ID }}" \
              --wait
          done

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            binary-*/*.tar.gz
            SHA256SUMS.txt
            SHA256SUMS.txt.asc
```

---

## Revenue Model

### Pricing Strategy

| Tier | Price | Target |
|------|-------|--------|
| Community | Free (source) | Hobbyists, contributors |
| Individual | $5-10 (one-time) | Solo developers |
| Team | $25-50 (one-time) | Small teams |
| Enterprise | Contact | Large organizations |

### Value Proposition for Paid Binaries

1. **Convenience** - No build environment needed
2. **Verification** - Signed and notarized
3. **Support** - Priority issue response
4. **Updates** - Notification of new releases
5. **Sustainability** - Funds ongoing development

### Package Maintainer Program

Per LICENSE-PROPRIETARY.txt Section 5:
> Package maintainers who distribute binaries through official package repositories
> (Homebrew, MacPorts, AUR, etc.) may do so under the terms of the zlib license.

This encourages ecosystem growth while preserving commercial value for direct sales.

---

## Precedents: Successful Projects Using This Model

| Project | Model | Revenue |
|---------|-------|---------|
| **Ardour** | Paid binaries, free source | Sustainable 8+ years |
| **Fritzing** | Mandatory donation for binaries | Revived dying project |
| **Sublime Text** | Nagware, source unavailable | Very successful |
| **Panic apps** | Paid binaries, some open source | Premium pricing works |

---

## Implementation Checklist

### Phase 1: Foundation
- [ ] Apple Developer Program enrollment ($99/year)
- [ ] Developer ID certificates (Application + Installer)
- [ ] GPG key for release signing
- [ ] Gumroad or Paddle account

### Phase 2: Build Pipeline
- [ ] Cross-platform CI builds (GitHub Actions or GitLab CI)
- [ ] Automated notarization for macOS
- [ ] Checksum generation
- [ ] GPG signing of checksums

### Phase 3: Distribution
- [ ] GitHub Releases with all artifacts
- [ ] Homebrew tap formula
- [ ] Install script
- [ ] Sales page (Gumroad/Paddle)

### Phase 4: Documentation
- [ ] Verification instructions
- [ ] GPG key import guide
- [ ] Installation options comparison
- [ ] License FAQ

---

## Costs Summary

| Item | Cost | Frequency |
|------|------|-----------|
| Apple Developer Program | $99 | Annual |
| Gumroad fees | 10% + payment | Per sale |
| Domain/hosting | ~$50 | Annual |
| **Total fixed costs** | ~$150/year | |

**Break-even**: 15-30 sales at $5-10 covers annual costs.

---

## References

- [Apple Developer ID](https://developer.apple.com/developer-id/)
- [Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [zlib License](https://zlib.net/zlib_license.html)
- [Ardour Download Model](https://community.ardour.org/download)
- [GoReleaser](https://goreleaser.com/)
- [AppImage Best Practices](https://docs.appimage.org/reference/best-practices.html)
