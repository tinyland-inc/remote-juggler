#!/bin/bash
# RemoteJuggler Shell Aliases and Functions
# ==========================================
#
# Add to your ~/.bashrc or ~/.zshrc:
#   source /path/to/shell-aliases.sh
#
# Or copy individual functions as needed.

# ==============================================================================
# Basic Aliases
# ==============================================================================

# Quick identity switching
alias rj='remote-juggler'
alias rjs='remote-juggler switch'
alias rjl='remote-juggler list'
alias rjst='remote-juggler status'
alias rjv='remote-juggler validate'

# Pin management (Trusted Workstation mode)
alias rjpin='remote-juggler pin status'
alias rjpins='remote-juggler pin store'
alias rjpinc='remote-juggler pin clear'

# ==============================================================================
# Smart Functions
# ==============================================================================

# Switch identity with confirmation
rj-switch() {
    local identity="$1"
    if [[ -z "$identity" ]]; then
        echo "Usage: rj-switch <identity>"
        echo "Available identities:"
        remote-juggler list
        return 1
    fi

    echo "Switching to identity: $identity"
    remote-juggler switch "$identity"

    # Show new status
    echo ""
    remote-juggler status --brief
}

# Clone with automatic identity detection
rj-clone() {
    local url="$1"
    shift

    if [[ -z "$url" ]]; then
        echo "Usage: rj-clone <git-url> [git-clone-options]"
        return 1
    fi

    # Detect identity from URL
    local identity
    identity=$(remote-juggler detect --url "$url" 2>/dev/null)

    if [[ -n "$identity" ]]; then
        echo "Detected identity: $identity"
        remote-juggler switch "$identity"
    fi

    git clone "$url" "$@"
}

# Interactive identity selector (requires fzf)
rj-select() {
    if ! command -v fzf &>/dev/null; then
        echo "This function requires fzf. Install with:"
        echo "  brew install fzf  # macOS"
        echo "  sudo apt install fzf  # Debian/Ubuntu"
        return 1
    fi

    local identity
    identity=$(remote-juggler list --json | jq -r '.identities | keys[]' | fzf --prompt="Select identity: ")

    if [[ -n "$identity" ]]; then
        remote-juggler switch "$identity"
    fi
}

# Show identity for current directory
rj-whoami() {
    echo "Current git config:"
    echo "  user.name:  $(git config user.name)"
    echo "  user.email: $(git config user.email)"
    echo "  signingkey: $(git config user.signingkey || echo 'not set')"
    echo ""
    echo "RemoteJuggler identity:"
    remote-juggler detect 2>/dev/null || echo "  (not in a git repository or no identity detected)"
}

# Validate all identities
rj-check() {
    echo "Validating all identities..."
    echo ""

    for identity in $(remote-juggler list --json | jq -r '.identities | keys[]'); do
        echo "Checking: $identity"
        if remote-juggler validate "$identity" --quiet; then
            echo "  ✓ OK"
        else
            echo "  ✗ FAILED"
        fi
    done
}

# ==============================================================================
# Git Workflow Integration
# ==============================================================================

# Commit with identity verification
rj-commit() {
    # Verify identity matches expected
    local current_email
    current_email=$(git config user.email)

    local expected_identity
    expected_identity=$(remote-juggler detect 2>/dev/null)

    if [[ -n "$expected_identity" ]]; then
        local expected_email
        expected_email=$(remote-juggler list --json | jq -r ".identities[\"$expected_identity\"].email")

        if [[ "$current_email" != "$expected_email" ]]; then
            echo "⚠️  Warning: Current email ($current_email) doesn't match expected identity ($expected_identity: $expected_email)"
            read -p "Switch to $expected_identity before committing? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                remote-juggler switch "$expected_identity"
            fi
        fi
    fi

    git commit "$@"
}

# Push with identity check
rj-push() {
    rj-whoami
    echo ""
    read -p "Push with this identity? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        git push "$@"
    fi
}

# ==============================================================================
# Prompt Integration
# ==============================================================================

# Get current identity for prompt (fast, cached)
__rj_identity() {
    # Cache for 60 seconds to avoid slowdown
    local cache_file="/tmp/.rj-identity-$$"
    local cache_age=60

    if [[ -f "$cache_file" ]]; then
        local file_age=$(($(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)))
        if [[ $file_age -lt $cache_age ]]; then
            cat "$cache_file"
            return
        fi
    fi

    local identity
    identity=$(remote-juggler detect --quiet 2>/dev/null)
    echo "$identity" > "$cache_file"
    echo "$identity"
}

# For bash PS1 (add to your prompt)
# PS1='[\u@\h \W]$(__rj_prompt) \$ '
__rj_prompt() {
    local identity
    identity=$(__rj_identity)
    if [[ -n "$identity" ]]; then
        echo " [rj:$identity]"
    fi
}

# For Starship prompt, add to starship.toml:
# [custom.remotejuggler]
# command = "remote-juggler detect --quiet 2>/dev/null"
# when = "test -d .git"
# format = "[$output]($style) "
# style = "blue"

# ==============================================================================
# Completion (Bash)
# ==============================================================================

_rj_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        switch|validate|rjs|rjv)
            # Complete with identity names
            local identities
            identities=$(remote-juggler list --json 2>/dev/null | jq -r '.identities | keys[]')
            COMPREPLY=($(compgen -W "$identities" -- "$cur"))
            return 0
            ;;
        remote-juggler|rj)
            COMPREPLY=($(compgen -W "switch list status validate detect pin setup sync-config gpg-status" -- "$cur"))
            return 0
            ;;
    esac
}

complete -F _rj_complete remote-juggler
complete -F _rj_complete rj
complete -F _rj_complete rjs
complete -F _rj_complete rjv
complete -F _rj_complete rj-switch

# ==============================================================================
# ZSH Completion
# ==============================================================================

if [[ -n "$ZSH_VERSION" ]]; then
    _rj_zsh_complete() {
        local identities
        identities=(${(f)"$(remote-juggler list --json 2>/dev/null | jq -r '.identities | keys[]')"})

        _arguments \
            '1:command:(switch list status validate detect pin setup sync-config gpg-status)' \
            '2:identity:($identities)'
    }

    compdef _rj_zsh_complete remote-juggler
    compdef _rj_zsh_complete rj
fi

# ==============================================================================
# Environment Setup
# ==============================================================================

# Auto-switch identity when changing directories (optional, can slow down shell)
# Uncomment to enable:
#
# rj_auto_switch() {
#     local identity
#     identity=$(remote-juggler detect --quiet 2>/dev/null)
#     if [[ -n "$identity" ]]; then
#         remote-juggler switch "$identity" --quiet
#     fi
# }
#
# # For bash
# PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }rj_auto_switch"
#
# # For zsh
# chpwd_functions+=(rj_auto_switch)
