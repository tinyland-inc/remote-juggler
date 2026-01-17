#!/bin/bash
# Generate macOS .icns and Linux icons from SVG source
# Requires: Inkscape or rsvg-convert, iconutil (macOS)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_ROOT/assets"
SVG_SOURCE="$ASSETS_DIR/remote-juggler.svg"

# Check for SVG source
if [[ ! -f "$SVG_SOURCE" ]]; then
    echo "Error: SVG source not found at $SVG_SOURCE"
    exit 1
fi

# Detect conversion tool
if command -v rsvg-convert &> /dev/null; then
    CONVERT_CMD="rsvg-convert"
elif command -v inkscape &> /dev/null; then
    CONVERT_CMD="inkscape"
else
    echo "Error: Neither rsvg-convert nor inkscape found"
    echo "Install with: brew install librsvg (macOS) or apt install librsvg2-bin (Linux)"
    exit 1
fi

convert_svg() {
    local size=$1
    local output=$2

    if [[ "$CONVERT_CMD" == "rsvg-convert" ]]; then
        rsvg-convert -w "$size" -h "$size" "$SVG_SOURCE" -o "$output"
    else
        inkscape "$SVG_SOURCE" -w "$size" -h "$size" -o "$output"
    fi
}

echo "Generating icons from $SVG_SOURCE..."

# --- macOS .icns generation ---
if [[ "$(uname)" == "Darwin" ]]; then
    echo "Generating macOS icon set..."

    ICONSET_DIR="$ASSETS_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"

    # Generate all required sizes for macOS iconset
    # Format: icon_WxH.png and icon_WxH@2x.png
    sizes=(16 32 128 256 512)
    for size in "${sizes[@]}"; do
        echo "  Generating ${size}x${size}..."
        convert_svg "$size" "$ICONSET_DIR/icon_${size}x${size}.png"

        # @2x retina version
        double=$((size * 2))
        echo "  Generating ${size}x${size}@2x (${double}px)..."
        convert_svg "$double" "$ICONSET_DIR/icon_${size}x${size}@2x.png"
    done

    # Generate .icns from iconset
    echo "Creating AppIcon.icns..."
    iconutil -c icns "$ICONSET_DIR" -o "$ASSETS_DIR/AppIcon.icns"

    echo "macOS icon created: $ASSETS_DIR/AppIcon.icns"

    # Cleanup iconset directory (optional)
    # rm -rf "$ICONSET_DIR"
fi

# --- Linux icon generation ---
echo "Generating Linux icons..."

LINUX_ICONS_DIR="$ASSETS_DIR/linux-icons"
mkdir -p "$LINUX_ICONS_DIR"

# Standard Linux icon sizes
linux_sizes=(16 22 24 32 48 64 128 256 512)
for size in "${linux_sizes[@]}"; do
    echo "  Generating ${size}x${size} PNG..."
    convert_svg "$size" "$LINUX_ICONS_DIR/remote-juggler-${size}.png"
done

echo "Linux icons created in: $LINUX_ICONS_DIR/"

# --- Tray-specific icons ---
echo "Generating tray icons..."

TRAY_DIR="$ASSETS_DIR/tray"
mkdir -p "$TRAY_DIR"

# Small tray icons (16, 22, 24, 32 are common tray sizes)
for size in 16 22 24 32; do
    convert_svg "$size" "$TRAY_DIR/tray-${size}.png"
done

echo "Tray icons created in: $TRAY_DIR/"

echo ""
echo "Icon generation complete!"
echo ""
echo "Files created:"
[[ -f "$ASSETS_DIR/AppIcon.icns" ]] && echo "  - $ASSETS_DIR/AppIcon.icns (macOS)"
echo "  - $LINUX_ICONS_DIR/ (Linux PNGs)"
echo "  - $TRAY_DIR/ (Tray PNGs)"
