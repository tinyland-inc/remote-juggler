#!/bin/sh
# RemoteJuggler Version Bump Script
# Usage: scripts/bump-version.sh <new-version>
# Example: scripts/bump-version.sh 2.1.0

set -eu

if [ $# -ne 1 ]; then
  echo "Usage: $0 <new-version>"
  echo "Example: $0 2.1.0"
  exit 1
fi

NEW_VERSION="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse semver components
MAJOR=$(echo "$NEW_VERSION" | cut -d. -f1)
MINOR=$(echo "$NEW_VERSION" | cut -d. -f2)
PATCH=$(echo "$NEW_VERSION" | cut -d. -f3 | cut -d- -f1)

echo "Bumping version to $NEW_VERSION (${MAJOR}.${MINOR}.${PATCH})"
echo ""

# Track files modified
MODIFIED=0

bump_file() {
  file="$1"
  pattern="$2"
  replacement="$3"
  desc="$4"

  if [ -f "$ROOT_DIR/$file" ]; then
    if grep -q "$pattern" "$ROOT_DIR/$file"; then
      sed -i "s|$pattern|$replacement|g" "$ROOT_DIR/$file"
      echo "  Updated: $file ($desc)"
      MODIFIED=$((MODIFIED + 1))
    fi
  fi
}

echo "=== Chapel Source ==="
bump_file "src/remote_juggler/Core.chpl" \
  'param VERSION = "[^"]*"' \
  "param VERSION = \"$NEW_VERSION\"" \
  "canonical VERSION"

bump_file "src/remote_juggler/Core.chpl" \
  'param VERSION_MINOR = [0-9]*' \
  "param VERSION_MINOR = $MINOR" \
  "VERSION_MINOR"

bump_file "src/remote_juggler/Core.chpl" \
  'param VERSION_PATCH = [0-9]*' \
  "param VERSION_PATCH = $PATCH" \
  "VERSION_PATCH"

bump_file "src/remote_juggler/ACP.chpl" \
  'param ACP_SERVER_VERSION = "[^"]*"' \
  "param ACP_SERVER_VERSION = \"$NEW_VERSION\"" \
  "ACP_SERVER_VERSION"

bump_file "src/remote_juggler/MCP.chpl" \
  'var serverVersion: string = "[^"]*"' \
  "var serverVersion: string = \"$NEW_VERSION\"" \
  "serverVersion"

bump_file "src/remote_juggler/MCP.chpl" \
  'Server version: [^"]*"' \
  "Server version: $NEW_VERSION\"" \
  "stderr log"

bump_file "src/remote_juggler/Setup.chpl" \
  '"version": "[^"]*"' \
  "\"version\": \"$NEW_VERSION\"" \
  "config version"

bump_file "src/remote_juggler/Setup.chpl" \
  '"setupVersion": "[^"]*"' \
  "\"setupVersion\": \"$NEW_VERSION\"" \
  "setupVersion"

echo ""
echo "=== Build Files ==="
bump_file "Mason.toml" \
  'version = "[^"]*"' \
  "version = \"$NEW_VERSION\"" \
  "Mason version"

bump_file "justfile" \
  'version := "[^"]*"' \
  "version := \"$NEW_VERSION\"" \
  "justfile version"

bump_file "flake.nix" \
  'version = "[0-9][^"]*"' \
  "version = \"$NEW_VERSION\"" \
  "Nix derivation"

bump_file "gtk-gui/Cargo.toml" \
  'version = "[^"]*"' \
  "version = \"$NEW_VERSION\"" \
  "Cargo version"

bump_file "tray/linux/Makefile" \
  'VERSION := [^ ]*' \
  "VERSION := $NEW_VERSION" \
  "Makefile VERSION"

echo ""
echo "=== Distribution ==="
bump_file "install.sh" \
  'REMOTE_JUGGLER_VERSION:-[^}]*' \
  "REMOTE_JUGGLER_VERSION:-$NEW_VERSION" \
  "default version"

bump_file "npm/package.json" \
  '"version": "[^"]*"' \
  "\"version\": \"$NEW_VERSION\"" \
  "npm version"

bump_file "server.json" \
  '"version": "[^"]*"' \
  "\"version\": \"$NEW_VERSION\"" \
  "MCP registry version"

echo ""
echo "=== Packaging ==="
bump_file "packaging/aur/PKGBUILD" \
  'pkgver=[^ ]*' \
  "pkgver=$(echo "$NEW_VERSION" | tr '-' '_')" \
  "AUR version"

# Info.plist has two version strings
bump_file "packaging/Info.plist" \
  '<string>[0-9]\.[0-9]\.[0-9][^<]*</string>' \
  "<string>$(echo "$NEW_VERSION" | cut -d- -f1)</string>" \
  "CFBundleVersion"

echo ""
echo "=== Workflows ==="
bump_file ".github/workflows/test-install.yml" \
  'REMOTE_JUGGLER_VERSION: "[^"]*"' \
  "REMOTE_JUGGLER_VERSION: \"$NEW_VERSION\"" \
  "test version"

echo ""
echo "=== Docs ==="
bump_file "docs/man/remote-juggler.1" \
  'RemoteJuggler v[^ ]*' \
  "RemoteJuggler v$NEW_VERSION" \
  "man page header"

bump_file "docs/man/remote-juggler.1" \
  '"RemoteJuggler [^"]*"' \
  "\"RemoteJuggler $NEW_VERSION\"" \
  "man page title"

echo ""
echo "=== Summary ==="
echo "Modified $MODIFIED files"
echo ""
echo "Manual steps remaining:"
echo "  1. Update CHANGELOG.md with release notes"
echo "  2. Update homebrew-tap/Formula/remote-juggler.rb URLs"
echo "  3. Update packaging/flatpak tags (replace_all: tag: vOLD → tag: vNEW)"
echo "  4. Run: cd gtk-gui && cargo update (to update Cargo.lock)"
echo "  5. Run: mason build (to update Mason.lock)"
echo "  6. Commit: git add -A && git commit -m 'chore: bump version to $NEW_VERSION'"
