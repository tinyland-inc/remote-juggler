#!/usr/bin/env bash
# RemoteJuggler Git Hooks Installer
# Installs post-checkout hook globally or per-repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Hooks to install (add more hooks here as needed)
HOOKS=("post-checkout" "pre-commit")

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Install RemoteJuggler git hooks for automatic identity switching.

OPTIONS:
    --global        Install globally for all repos (via git template)
    --local         Install in current repository only
    --repo PATH     Install in specified repository
    --uninstall     Remove hooks
    --check         Check if hooks are installed
    -h, --help      Show this help message

EXAMPLES:
    # Install globally for all new repos
    $0 --global

    # Install in current repo
    $0 --local

    # Install in specific repo
    $0 --repo ~/git/myproject

    # Check installation status
    $0 --check

    # Uninstall global hooks
    $0 --global --uninstall

GLOBAL INSTALLATION:
    Hooks are installed to ~/.git-templates/hooks/ and git is configured
    to use this template directory. All new clones and inits will have the hooks.

LOCAL INSTALLATION:
    Hooks are installed directly to .git/hooks/ in the repository.
    Only affects that specific repository.

POST-CHECKOUT HOOK:
    Runs after 'git checkout' and automatically detects the appropriate
    identity based on the repository's remote URL, then switches to it.

EOF
    exit 0
}

install_global() {
    local template_dir="$HOME/.git-templates/hooks"

    echo "Installing RemoteJuggler hooks globally..."

    # Create template directory
    mkdir -p "$template_dir"

    # Install all hooks
    for hook in "${HOOKS[@]}"; do
        if [ -f "$SCRIPT_DIR/$hook" ]; then
            cp "$SCRIPT_DIR/$hook" "$template_dir/$hook"
            chmod +x "$template_dir/$hook"
            echo "  ✓ Installed: $hook"
        fi
    done

    # Configure git to use template
    git config --global init.templateDir "$HOME/.git-templates"

    echo "✅ Global hooks installed to: $template_dir"
    echo "ℹ️  All new 'git clone' and 'git init' will include the hooks"
    echo "ℹ️  To add to existing repos, run: $0 --local"
}

install_local() {
    local repo_path="${1:-.}"

    # Check if we're in a git repository
    if [ ! -d "$repo_path/.git" ]; then
        echo "❌ Error: $repo_path is not a git repository"
        exit 1
    fi

    local hooks_dir="$repo_path/.git/hooks"

    echo "Installing RemoteJuggler hooks in: $repo_path"

    # Install all hooks
    for hook in "${HOOKS[@]}"; do
        if [ -f "$SCRIPT_DIR/$hook" ]; then
            cp "$SCRIPT_DIR/$hook" "$hooks_dir/$hook"
            chmod +x "$hooks_dir/$hook"
            echo "  ✓ Installed: $hook"
        fi
    done

    echo "✅ Hooks installed to: $hooks_dir"
}

uninstall_global() {
    local template_dir="$HOME/.git-templates/hooks"

    echo "Uninstalling RemoteJuggler global hooks..."

    for hook in "${HOOKS[@]}"; do
        if [ -f "$template_dir/$hook" ]; then
            rm "$template_dir/$hook"
            echo "  ✓ Removed: $hook"
        else
            echo "  ℹ️  Hook not found: $hook"
        fi
    done

    # Check if template dir is empty
    if [ -d "$template_dir" ] && [ -z "$(ls -A "$template_dir")" ]; then
        rmdir "$template_dir"
        echo "✅ Removed empty hooks directory"
    fi

    # Don't unset init.templateDir as user might have other hooks
    echo "ℹ️  git init.templateDir still set to: $(git config --global init.templateDir)"
}

uninstall_local() {
    local repo_path="${1:-.}"
    local hooks_dir="$repo_path/.git/hooks"

    echo "Uninstalling RemoteJuggler hooks from: $repo_path"

    for hook in "${HOOKS[@]}"; do
        if [ -f "$hooks_dir/$hook" ]; then
            # Check if it's our hook
            if grep -q "RemoteJuggler" "$hooks_dir/$hook" 2>/dev/null; then
                rm "$hooks_dir/$hook"
                echo "  ✓ Removed: $hook"
            else
                echo "  ⚠️  Warning: $hook exists but is not a RemoteJuggler hook"
                echo "     Skipping removal to preserve custom hook"
            fi
        else
            echo "  ℹ️  Hook not found: $hook"
        fi
    done
}

check_installation() {
    echo "Checking RemoteJuggler hooks installation..."
    echo

    # Check global
    local template_dir="$(git config --global init.templateDir 2>/dev/null || true)"
    echo "Global hooks (template: ${template_dir:-not set}):"
    if [ -n "$template_dir" ]; then
        for hook in "${HOOKS[@]}"; do
            if [ -f "$template_dir/hooks/$hook" ]; then
                echo "  ✅ $hook: INSTALLED"
            else
                echo "  ❌ $hook: NOT INSTALLED"
            fi
        done
    else
        echo "  ❌ Template directory not configured"
    fi

    echo

    # Check local (current directory)
    if [ -d ".git" ]; then
        echo "Local hooks (current repo):"
        for hook in "${HOOKS[@]}"; do
            if [ -f ".git/hooks/$hook" ]; then
                if grep -q "RemoteJuggler" ".git/hooks/$hook" 2>/dev/null; then
                    echo "  ✅ $hook: INSTALLED"
                else
                    echo "  ⚠️  $hook: CUSTOM HOOK DETECTED"
                fi
            else
                echo "  ❌ $hook: NOT INSTALLED"
            fi
        done
    else
        echo "ℹ️  Not in a git repository"
    fi
}

# Parse arguments
MODE=""
REPO_PATH=""
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --global)
            MODE="global"
            shift
            ;;
        --local)
            MODE="local"
            shift
            ;;
        --repo)
            MODE="local"
            REPO_PATH="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --check)
            check_installation
            exit 0
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Require a mode
if [ -z "$MODE" ]; then
    echo "Error: Must specify --global or --local"
    echo "Run with --help for usage information"
    exit 1
fi

# Execute
if [ "$UNINSTALL" = true ]; then
    if [ "$MODE" = "global" ]; then
        uninstall_global
    else
        uninstall_local "$REPO_PATH"
    fi
else
    if [ "$MODE" = "global" ]; then
        install_global
    else
        install_local "$REPO_PATH"
    fi
fi
