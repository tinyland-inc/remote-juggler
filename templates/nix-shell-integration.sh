#!/usr/bin/env bash
# RemoteJuggler Nix shell integration
# Source this in your nix-shell or flake devShell shellHook
#
# Usage in flake.nix:
#   shellHook = ''
#     source ${./templates/nix-shell-integration.sh}
#   '';

# Auto-detect and switch identity when entering nix-shell
if command -v remote-juggler >/dev/null 2>&1; then
    # Only auto-switch if in a git repository
    if [ -d .git ] || git rev-parse --git-dir >/dev/null 2>&1; then
        DETECTED=$(remote-juggler detect --quiet 2>/dev/null)
        CURRENT=$(remote-juggler status --quiet 2>/dev/null)

        if [ -n "$DETECTED" ] && [ "$DETECTED" != "$CURRENT" ]; then
            echo "RemoteJuggler: Auto-switching to '$DETECTED' identity"
            remote-juggler switch "$DETECTED" --setRemote=false 2>/dev/null || {
                echo "RemoteJuggler: Switch failed, continuing with current identity"
            }
        fi

        # Show current identity
        if [ -n "$CURRENT" ]; then
            echo "RemoteJuggler: Using identity '$CURRENT'"
        fi
    fi
fi

# Optional: Add RemoteJuggler aliases to the shell session
# alias rj='remote-juggler'
# alias rjst='remote-juggler status'
# alias rjsw='remote-juggler switch'
# alias rjls='remote-juggler list'
