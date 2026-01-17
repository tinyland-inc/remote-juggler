#!/bin/bash
# Create macOS .app bundle for RemoteJuggler Tray
# Usage: ./scripts/create-app-bundle.sh [version]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-2.0.0}"
APP_NAME="RemoteJuggler"
BUNDLE_ID="dev.tinyland.remote-juggler"

# Output directories
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"

# Source directories
TRAY_DIR="$PROJECT_ROOT/tray/darwin"
ASSETS_DIR="$PROJECT_ROOT/assets"
PACKAGING_DIR="$PROJECT_ROOT/packaging"

# Signing identity (auto-detect if not set)
SIGNING_IDENTITY="${SIGNING_IDENTITY_APP:-}"

echo "=== Creating ${APP_NAME}.app bundle v${VERSION} ==="

# Clean previous build
rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR"

# Step 1: Build Swift tray app
echo ""
echo "Step 1: Building SwiftUI tray application..."
cd "$TRAY_DIR"

# Use Xcode if available, otherwise fall back to default swift
if [[ -d "/Applications/Xcode.app" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    SWIFT_CMD="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
else
    SWIFT_CMD="swift"
fi

if $SWIFT_CMD build -c release 2>&1; then
    echo "  Swift build successful"
else
    echo "  ERROR: Swift build failed"
    exit 1
fi

# Locate built binary
SWIFT_BINARY="$TRAY_DIR/.build/release/RemoteJugglerTray"
if [[ ! -f "$SWIFT_BINARY" ]]; then
    # Try arm64-apple-macosx path
    SWIFT_BINARY=$(find "$TRAY_DIR/.build" -name "RemoteJugglerTray" -type f -perm +111 2>/dev/null | head -1)
fi

if [[ ! -f "$SWIFT_BINARY" ]]; then
    echo "  ERROR: Cannot find built binary"
    exit 1
fi
echo "  Binary: $SWIFT_BINARY"

# Step 2: Create app bundle structure
echo ""
echo "Step 2: Creating app bundle structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$SWIFT_BINARY" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

# Step 3: Create/copy Info.plist
echo ""
echo "Step 3: Creating Info.plist..."

if [[ -f "$PACKAGING_DIR/Info.plist" ]]; then
    # Update version in existing plist
    sed -e "s/2\.0\.0/${VERSION}/g" "$PACKAGING_DIR/Info.plist" > "$APP_BUNDLE/Contents/Info.plist"
else
    # Create Info.plist
    cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 Tinyland. All rights reserved.</string>
</dict>
</plist>
EOF
fi

# Step 4: Copy resources
echo ""
echo "Step 4: Copying resources..."

# Copy app icon
if [[ -f "$ASSETS_DIR/AppIcon.icns" ]]; then
    cp "$ASSETS_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo "  Copied AppIcon.icns"
fi

# Optionally bundle CLI binary if it exists
CLI_BINARY="$PROJECT_ROOT/remote-juggler-darwin-arm64"
if [[ -f "$CLI_BINARY" ]]; then
    cp "$CLI_BINARY" "$APP_BUNDLE/Contents/Resources/remote-juggler"
    chmod +x "$APP_BUNDLE/Contents/Resources/remote-juggler"
    echo "  Bundled CLI binary"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Step 5: Code signing
echo ""
echo "Step 5: Code signing..."

# Auto-detect signing identity if not provided
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | \
        grep "Developer ID Application" | \
        head -1 | \
        sed 's/.*"\(.*\)".*/\1/')
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "  Signing with: $SIGNING_IDENTITY"

    # Sign embedded resources first
    if [[ -f "$APP_BUNDLE/Contents/Resources/remote-juggler" ]]; then
        codesign --force --options runtime --timestamp \
            --sign "$SIGNING_IDENTITY" \
            "$APP_BUNDLE/Contents/Resources/remote-juggler"
    fi

    # Sign main binary
    codesign --force --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

    # Sign the bundle
    codesign --force --deep --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$APP_BUNDLE"

    # Verify signature
    echo ""
    echo "  Verifying signature..."
    codesign --verify --verbose=2 "$APP_BUNDLE"
    spctl --assess --type execute --verbose=2 "$APP_BUNDLE" 2>&1 || true

    echo "  Code signing complete"
else
    echo "  WARNING: No signing identity found - app will be unsigned"
    echo "  Set SIGNING_IDENTITY_APP environment variable to sign"
fi

# Step 6: Summary
echo ""
echo "=== Build Complete ==="
echo ""
echo "App Bundle: $APP_BUNDLE"
echo "Version: $VERSION"
ls -la "$APP_BUNDLE"
echo ""

# Calculate size
SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo "Bundle Size: $SIZE"

# Show bundle contents
echo ""
echo "Contents:"
find "$APP_BUNDLE" -type f | sed "s|$APP_BUNDLE|  ${APP_NAME}.app|"

echo ""
echo "Next steps:"
echo "  1. Test: open '$APP_BUNDLE'"
echo "  2. Create DMG: ./scripts/create-dmg.sh $VERSION"
echo "  3. Notarize: xcrun notarytool submit <dmg> --wait"
