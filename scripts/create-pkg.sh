#!/bin/bash
# RemoteJuggler Local PKG Build Script
# Creates a signed macOS PKG installer locally (requires Developer ID certificates)
#
# Usage: ./scripts/create-pkg.sh [version]
#
# Prerequisites:
#   - Developer ID Application certificate in Keychain
#   - Developer ID Installer certificate in Keychain
#   - Xcode Command Line Tools installed
#
# Environment Variables (optional):
#   SIGNING_IDENTITY_APP    - Developer ID Application identity (auto-detected if not set)
#   SIGNING_IDENTITY_PKG    - Developer ID Installer identity (auto-detected if not set)
#   NOTARIZE                - Set to "1" to also notarize the PKG
#   APPLE_ID                - Apple ID for notarization
#   APPLE_TEAM_ID           - Team ID for notarization
#   KEYCHAIN_PROFILE        - Notarytool keychain profile name

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Version from argument or Core.chpl
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    if [ -f "$PROJECT_ROOT/src/remote_juggler/Core.chpl" ]; then
        VERSION=$(grep -o 'VERSION = "[^"]*"' "$PROJECT_ROOT/src/remote_juggler/Core.chpl" | cut -d'"' -f2)
    fi
fi
VERSION="${VERSION:-0.0.0}"

echo "=== RemoteJuggler PKG Builder ==="
echo "Version: $VERSION"
echo ""

# Paths
BINARY="$PROJECT_ROOT/target/release/remote-juggler"
PKG_ROOT="$PROJECT_ROOT/build/pkg-root"
PKG_OUTPUT="$PROJECT_ROOT/build/installer"
PKG_UNSIGNED="$PKG_OUTPUT/RemoteJuggler-$VERSION-unsigned.pkg"
PKG_SIGNED="$PKG_OUTPUT/RemoteJuggler-$VERSION.pkg"

# Check for binary
if [ ! -f "$BINARY" ]; then
    echo "Binary not found at $BINARY"
    echo "Run 'make release' first to build the binary."
    exit 1
fi

# Detect signing identities if not provided
if [ -z "${SIGNING_IDENTITY_APP:-}" ]; then
    SIGNING_IDENTITY_APP=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
fi

if [ -z "${SIGNING_IDENTITY_PKG:-}" ]; then
    SIGNING_IDENTITY_PKG=$(security find-identity -v | grep "Developer ID Installer" | head -1 | sed 's/.*"\(.*\)".*/\1/' || true)
fi

echo "Signing Identities:"
echo "  Application: ${SIGNING_IDENTITY_APP:-<not found>}"
echo "  Installer:   ${SIGNING_IDENTITY_PKG:-<not found>}"
echo ""

# Create directories
mkdir -p "$PKG_ROOT/usr/local/bin"
mkdir -p "$PKG_OUTPUT"

# Copy binary
echo "Copying binary..."
cp "$BINARY" "$PKG_ROOT/usr/local/bin/remote-juggler"
chmod +x "$PKG_ROOT/usr/local/bin/remote-juggler"

# Sign binary if identity available
if [ -n "$SIGNING_IDENTITY_APP" ]; then
    echo "Signing binary with hardened runtime..."
    codesign --force --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY_APP" \
        "$PKG_ROOT/usr/local/bin/remote-juggler"

    echo "Verifying binary signature..."
    codesign --verify --verbose=2 "$PKG_ROOT/usr/local/bin/remote-juggler"
else
    echo "WARNING: No Developer ID Application certificate found - binary will be unsigned"
fi

# Build unsigned PKG
echo ""
echo "Building PKG..."
pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "dev.tinyland.remote-juggler" \
    --version "$VERSION" \
    --install-location "/" \
    "$PKG_UNSIGNED"

# Sign PKG if identity available
if [ -n "$SIGNING_IDENTITY_PKG" ]; then
    echo "Signing PKG..."
    productsign \
        --sign "$SIGNING_IDENTITY_PKG" \
        "$PKG_UNSIGNED" \
        "$PKG_SIGNED"

    rm "$PKG_UNSIGNED"

    echo "Verifying PKG signature..."
    pkgutil --check-signature "$PKG_SIGNED"

    # Notarize if requested
    if [ "${NOTARIZE:-}" = "1" ]; then
        echo ""
        echo "Submitting for notarization..."

        if [ -n "${KEYCHAIN_PROFILE:-}" ]; then
            # Use keychain profile (recommended for local use)
            xcrun notarytool submit "$PKG_SIGNED" \
                --keychain-profile "$KEYCHAIN_PROFILE" \
                --wait
        elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
            # Use environment variables (will prompt for password)
            xcrun notarytool submit "$PKG_SIGNED" \
                --apple-id "$APPLE_ID" \
                --team-id "$APPLE_TEAM_ID" \
                --wait
        else
            echo "ERROR: NOTARIZE=1 but no credentials provided"
            echo "Set KEYCHAIN_PROFILE or (APPLE_ID + APPLE_TEAM_ID)"
            exit 1
        fi

        echo "Stapling notarization ticket..."
        xcrun stapler staple "$PKG_SIGNED"

        echo "Validating stapled PKG..."
        xcrun stapler validate "$PKG_SIGNED"
    fi
else
    echo "WARNING: No Developer ID Installer certificate found - PKG will be unsigned"
    mv "$PKG_UNSIGNED" "$PKG_SIGNED"
fi

# Generate checksum
echo ""
echo "Generating checksum..."
shasum -a 256 "$PKG_SIGNED" > "$PKG_SIGNED.sha256"

# Cleanup
rm -rf "$PKG_ROOT"

echo ""
echo "=== Build Complete ==="
echo "PKG: $PKG_SIGNED"
echo "SHA: $PKG_SIGNED.sha256"
echo ""

# Verify with Gatekeeper if signed
if [ -n "$SIGNING_IDENTITY_PKG" ]; then
    echo "Gatekeeper assessment:"
    spctl --assess --type install --verbose=2 "$PKG_SIGNED" 2>&1 || true
fi
