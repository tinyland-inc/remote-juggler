#!/bin/bash
# RemoteJuggler Post-Installation Script
# Called after package installation to set up configuration and completions
#
# Usage: Called automatically by RPM/DEB/pacman package managers

set -e

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/remote-juggler"
BINARY="remote-juggler"

echo "=== RemoteJuggler Post-Installation ==="
echo ""

# Create system config directory
if [ ! -d "$CONFIG_DIR" ]; then
    echo "Creating config directory: $CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"
fi

# Set up shell completions if the binary supports it and directories exist
echo "Setting up shell completions..."

# Bash completions
if [ -d /etc/bash_completion.d ]; then
    if "$INSTALL_DIR/$BINARY" completions bash > /etc/bash_completion.d/remote-juggler 2>/dev/null; then
        echo "  Installed bash completions to /etc/bash_completion.d/remote-juggler"
    else
        echo "  Skipped bash completions (command not available)"
    fi
fi

# Zsh completions
if [ -d /usr/share/zsh/site-functions ]; then
    if "$INSTALL_DIR/$BINARY" completions zsh > /usr/share/zsh/site-functions/_remote-juggler 2>/dev/null; then
        echo "  Installed zsh completions to /usr/share/zsh/site-functions/_remote-juggler"
    else
        echo "  Skipped zsh completions (command not available)"
    fi
fi

# Fish completions
if [ -d /usr/share/fish/vendor_completions.d ]; then
    if "$INSTALL_DIR/$BINARY" completions fish > /usr/share/fish/vendor_completions.d/remote-juggler.fish 2>/dev/null; then
        echo "  Installed fish completions to /usr/share/fish/vendor_completions.d/remote-juggler.fish"
    else
        echo "  Skipped fish completions (command not available)"
    fi
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "RemoteJuggler has been installed to: $INSTALL_DIR/$BINARY"
echo ""
echo "Next steps:"
echo "  1. Create your configuration: remote-juggler config init"
echo "  2. Import from SSH config:    remote-juggler config import"
echo "  3. List identities:           remote-juggler list"
echo "  4. Switch identity:           remote-juggler switch <name>"
echo ""
echo "For MCP server integration with Claude Code:"
echo "  Add to ~/.config/claude/mcp.json or VS Code settings"
echo ""
echo "Run 'remote-juggler --help' for more information."
