#!/bin/bash
# RemoteJuggler Pre-Removal Script
# Called before package removal to clean up system-wide files
#
# Usage: Called automatically by RPM/DEB/pacman package managers

set -e

echo "=== RemoteJuggler Pre-Removal ==="
echo ""

# Remove shell completions
echo "Removing shell completions..."

if [ -f /etc/bash_completion.d/remote-juggler ]; then
    rm -f /etc/bash_completion.d/remote-juggler
    echo "  Removed /etc/bash_completion.d/remote-juggler"
fi

if [ -f /usr/share/zsh/site-functions/_remote-juggler ]; then
    rm -f /usr/share/zsh/site-functions/_remote-juggler
    echo "  Removed /usr/share/zsh/site-functions/_remote-juggler"
fi

if [ -f /usr/share/fish/vendor_completions.d/remote-juggler.fish ]; then
    rm -f /usr/share/fish/vendor_completions.d/remote-juggler.fish
    echo "  Removed /usr/share/fish/vendor_completions.d/remote-juggler.fish"
fi

echo ""
echo "=== Pre-Removal Complete ==="
echo ""
echo "Note: User configuration in ~/.config/remote-juggler/ has been preserved."
echo "      Remove it manually if no longer needed."
