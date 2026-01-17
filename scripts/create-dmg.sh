#!/bin/bash
# Create macOS DMG installer for RemoteJuggler
# Usage: ./scripts/create-dmg.sh [version]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-2.0.0}"
APP_NAME="RemoteJuggler"
BUNDLE_ID="dev.tinyland.remote-juggler"

# Paths
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}-darwin-arm64"
DMG_PATH="$BUILD_DIR/${DMG_NAME}.dmg"
DMG_TEMP="$BUILD_DIR/dmg-temp"

# Signing identities (auto-detect if not set)
SIGNING_IDENTITY_APP="${SIGNING_IDENTITY_APP:-}"
SIGNING_IDENTITY_INSTALLER="${SIGNING_IDENTITY_INSTALLER:-}"

# Notarization credentials (optional)
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-QP994XQKNH}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-}"

echo "=== Creating ${DMG_NAME}.dmg ==="

# Check for app bundle
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "ERROR: App bundle not found at $APP_BUNDLE"
    echo "Run ./scripts/create-app-bundle.sh first"
    exit 1
fi

# Clean previous builds
rm -rf "$DMG_TEMP" "$DMG_PATH"
mkdir -p "$DMG_TEMP"

# Step 1: Create DMG contents
echo ""
echo "Step 1: Preparing DMG contents..."

# Copy app bundle
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create Applications symlink
ln -s /Applications "$DMG_TEMP/Applications"

# Create background image directory (optional)
# mkdir -p "$DMG_TEMP/.background"

# Step 2: Create DMG
echo ""
echo "Step 2: Creating DMG image..."

# Calculate size (add 20MB padding)
SIZE_KB=$(du -sk "$DMG_TEMP" | cut -f1)
SIZE_MB=$(( (SIZE_KB / 1024) + 20 ))

# Create temporary DMG
hdiutil create -srcfolder "$DMG_TEMP" \
    -volname "$APP_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size ${SIZE_MB}m \
    "$BUILD_DIR/temp.dmg"

# Mount for customization
MOUNT_DIR=$(hdiutil attach -readwrite -noverify "$BUILD_DIR/temp.dmg" | \
    grep -E '^/dev/' | tail -1 | awk '{print $NF}')

echo "  Mounted at: $MOUNT_DIR"

# Step 3: Customize DMG appearance (optional)
echo ""
echo "Step 3: Customizing DMG window..."

# Use AppleScript to set window properties
osascript << EOF
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 920, 440}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set position of item "${APP_NAME}.app" of container window to {130, 150}
        set position of item "Applications" of container window to {390, 150}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

sync

# Unmount
hdiutil detach "$MOUNT_DIR"

# Step 4: Convert to compressed DMG
echo ""
echo "Step 4: Compressing DMG..."

hdiutil convert "$BUILD_DIR/temp.dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

rm "$BUILD_DIR/temp.dmg"

# Step 5: Sign DMG
echo ""
echo "Step 5: Signing DMG..."

# Auto-detect signing identity if not provided
if [[ -z "$SIGNING_IDENTITY_APP" ]]; then
    SIGNING_IDENTITY_APP=$(security find-identity -v -p codesigning 2>/dev/null | \
        grep "Developer ID Application" | \
        head -1 | \
        sed 's/.*"\(.*\)".*/\1/')
fi

if [[ -n "$SIGNING_IDENTITY_APP" ]]; then
    echo "  Signing with: $SIGNING_IDENTITY_APP"
    codesign --force --sign "$SIGNING_IDENTITY_APP" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
    echo "  DMG signed successfully"
else
    echo "  WARNING: No signing identity - DMG will be unsigned"
fi

# Step 6: Notarization (optional)
echo ""
echo "Step 6: Notarization..."

NOTARIZED=false

if [[ -n "$KEYCHAIN_PROFILE" ]]; then
    echo "  Using keychain profile: $KEYCHAIN_PROFILE"
    if xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait 2>&1 | tee "$BUILD_DIR/notarization.log"; then

        echo "  Stapling notarization ticket..."
        xcrun stapler staple "$DMG_PATH"
        NOTARIZED=true
    else
        echo "  WARNING: Notarization failed"
    fi
elif [[ -n "$APPLE_ID" ]] && [[ -n "$APPLE_NOTARIZE_PASSWORD" ]]; then
    echo "  Using Apple ID credentials..."
    if xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_NOTARIZE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait 2>&1 | tee "$BUILD_DIR/notarization.log"; then

        echo "  Stapling notarization ticket..."
        xcrun stapler staple "$DMG_PATH"
        NOTARIZED=true
    else
        echo "  WARNING: Notarization failed"
    fi
else
    echo "  Skipping notarization (no credentials provided)"
    echo "  Set KEYCHAIN_PROFILE or APPLE_ID + APPLE_NOTARIZE_PASSWORD"
fi

# Cleanup
rm -rf "$DMG_TEMP"

# Step 7: Generate checksums
echo ""
echo "Step 7: Generating checksums..."

shasum -a 256 "$DMG_PATH" > "${DMG_PATH}.sha256"
cat "${DMG_PATH}.sha256"

# Summary
echo ""
echo "=== DMG Creation Complete ==="
echo ""
echo "DMG: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
echo "Signed: $(if [[ -n "$SIGNING_IDENTITY_APP" ]]; then echo "Yes"; else echo "No"; fi)"
echo "Notarized: $NOTARIZED"
echo ""

if [[ "$NOTARIZED" == "true" ]]; then
    echo "DMG is ready for distribution!"
else
    echo "To notarize manually:"
    echo "  xcrun notarytool submit '$DMG_PATH' --apple-id YOUR_APPLE_ID --team-id $APPLE_TEAM_ID --wait"
    echo "  xcrun stapler staple '$DMG_PATH'"
fi

echo ""
echo "To verify:"
echo "  spctl --assess --type open --context context:primary-signature -vvv '$DMG_PATH'"
