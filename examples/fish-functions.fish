# RemoteJuggler Fish Shell Functions
# ===================================
#
# Install by copying to ~/.config/fish/functions/
# Or source from config.fish:
#   source /path/to/fish-functions.fish

# ==============================================================================
# Abbreviations (like aliases but expand when typed)
# ==============================================================================

abbr -a rj 'remote-juggler'
abbr -a rjs 'remote-juggler switch'
abbr -a rjl 'remote-juggler list'
abbr -a rjst 'remote-juggler status'
abbr -a rjv 'remote-juggler validate'

# ==============================================================================
# Functions
# ==============================================================================

# Switch identity with status display
function rj-switch -d "Switch RemoteJuggler identity"
    if test (count $argv) -eq 0
        echo "Usage: rj-switch <identity>"
        echo "Available identities:"
        remote-juggler list
        return 1
    end

    set -l identity $argv[1]
    echo "Switching to identity: $identity"
    remote-juggler switch $identity

    echo ""
    remote-juggler status --brief
end

# Clone with automatic identity detection
function rj-clone -d "Clone repository with automatic identity detection"
    if test (count $argv) -eq 0
        echo "Usage: rj-clone <git-url> [git-clone-options]"
        return 1
    end

    set -l url $argv[1]
    set -e argv[1]

    # Detect identity from URL
    set -l identity (remote-juggler detect --url $url 2>/dev/null)

    if test -n "$identity"
        echo "Detected identity: $identity"
        remote-juggler switch $identity
    end

    git clone $url $argv
end

# Interactive identity selector (requires fzf)
function rj-select -d "Interactively select and switch identity"
    if not type -q fzf
        echo "This function requires fzf. Install with:"
        echo "  brew install fzf  # macOS"
        echo "  sudo apt install fzf  # Debian/Ubuntu"
        return 1
    end

    set -l identity (remote-juggler list --json | jq -r '.identities | keys[]' | fzf --prompt="Select identity: ")

    if test -n "$identity"
        remote-juggler switch $identity
    end
end

# Show current identity
function rj-whoami -d "Show current git identity"
    echo "Current git config:"
    echo "  user.name:  "(git config user.name)
    echo "  user.email: "(git config user.email)
    echo "  signingkey: "(git config user.signingkey; or echo 'not set')
    echo ""
    echo "RemoteJuggler identity:"
    remote-juggler detect 2>/dev/null; or echo "  (not in a git repository or no identity detected)"
end

# Validate all identities
function rj-check -d "Validate all configured identities"
    echo "Validating all identities..."
    echo ""

    for identity in (remote-juggler list --json | jq -r '.identities | keys[]')
        echo "Checking: $identity"
        if remote-juggler validate $identity --quiet
            echo "  ✓ OK"
        else
            echo "  ✗ FAILED"
        end
    end
end

# Commit with identity verification
function rj-commit -d "Commit with identity verification"
    set -l current_email (git config user.email)
    set -l expected_identity (remote-juggler detect 2>/dev/null)

    if test -n "$expected_identity"
        set -l expected_email (remote-juggler list --json | jq -r ".identities[\"$expected_identity\"].email")

        if test "$current_email" != "$expected_email"
            echo "⚠️  Warning: Current email ($current_email) doesn't match expected identity ($expected_identity: $expected_email)"
            read -P "Switch to $expected_identity before committing? [y/N] " -n 1 confirm
            if test "$confirm" = "y" -o "$confirm" = "Y"
                remote-juggler switch $expected_identity
            end
        end
    end

    git commit $argv
end

# Push with identity confirmation
function rj-push -d "Push with identity confirmation"
    rj-whoami
    echo ""
    read -P "Push with this identity? [Y/n] " -n 1 confirm
    if test "$confirm" != "n" -a "$confirm" != "N"
        git push $argv
    end
end

# ==============================================================================
# Prompt Integration
# ==============================================================================

# Get current identity for prompt
function __rj_identity -d "Get current RemoteJuggler identity (cached)"
    # Simple cache to avoid slowdown
    set -l cache_file /tmp/.rj-identity-fish-$fish_pid

    if test -f $cache_file
        set -l file_age (math (date +%s) - (stat -f %m $cache_file 2>/dev/null; or stat -c %Y $cache_file 2>/dev/null))
        if test $file_age -lt 60
            cat $cache_file
            return
        end
    end

    set -l identity (remote-juggler detect --quiet 2>/dev/null)
    echo $identity > $cache_file
    echo $identity
end

# Add to your fish_prompt function:
# function fish_prompt
#     set -l identity (__rj_identity)
#     if test -n "$identity"
#         set_color blue
#         echo -n "[rj:$identity] "
#         set_color normal
#     end
#     # ... rest of your prompt
# end

# Or use with Tide/Starship - see shell-aliases.sh for Starship config

# ==============================================================================
# Completions
# ==============================================================================

# Complete identity names for switch/validate commands
function __fish_rj_identities
    remote-juggler list --json 2>/dev/null | jq -r '.identities | keys[]'
end

# Main command completions
complete -c remote-juggler -f
complete -c remote-juggler -n "__fish_use_subcommand" -a "switch" -d "Switch to identity"
complete -c remote-juggler -n "__fish_use_subcommand" -a "list" -d "List identities"
complete -c remote-juggler -n "__fish_use_subcommand" -a "status" -d "Show current status"
complete -c remote-juggler -n "__fish_use_subcommand" -a "validate" -d "Validate identity"
complete -c remote-juggler -n "__fish_use_subcommand" -a "detect" -d "Detect identity for repo"
complete -c remote-juggler -n "__fish_use_subcommand" -a "pin" -d "PIN management"
complete -c remote-juggler -n "__fish_use_subcommand" -a "setup" -d "Run setup wizard"
complete -c remote-juggler -n "__fish_use_subcommand" -a "sync-config" -d "Sync configuration"
complete -c remote-juggler -n "__fish_use_subcommand" -a "gpg-status" -d "Show GPG status"

# Identity completions for switch/validate
complete -c remote-juggler -n "__fish_seen_subcommand_from switch validate" -a "(__fish_rj_identities)"

# Alias completions
complete -c rj -w remote-juggler
complete -c rjs -n "__fish_use_subcommand" -a "(__fish_rj_identities)"
complete -c rjv -n "__fish_use_subcommand" -a "(__fish_rj_identities)"

# ==============================================================================
# Auto-switch on directory change (optional)
# ==============================================================================

# Uncomment to enable automatic identity switching when changing directories:
#
# function __rj_auto_switch --on-variable PWD
#     if test -d .git
#         set -l identity (remote-juggler detect --quiet 2>/dev/null)
#         if test -n "$identity"
#             remote-juggler switch $identity --quiet
#         end
#     end
# end
