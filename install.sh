#!/bin/sh
# RemoteJuggler - POSIX-Compatible Rootless Installation Script
# https://gitlab.com/tinyland/projects/remote-juggler
#
# Usage:
#   curl -fsSL https://gitlab.com/tinyland/projects/remote-juggler/-/raw/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/tinyland-inc/remote-juggler/main/install.sh | sh
#
# Options:
#   --help              Show this help message
#   --version VERSION   Install specific version (or set REMOTE_JUGGLER_VERSION)

set -eu

# Configuration
GITLAB_REPO="https://gitlab.com/tinyland/projects/remote-juggler"
GITHUB_REPO="https://github.com/tinyland-inc/remote-juggler"
BINARY_NAME="remote-juggler"

# Version: use env var, or detect latest from GitHub, or fallback
if [ -n "${REMOTE_JUGGLER_VERSION:-}" ]; then
  VERSION="$REMOTE_JUGGLER_VERSION"
elif command -v curl >/dev/null 2>&1; then
  VERSION=$(curl -fsSL https://api.github.com/repos/tinyland-inc/remote-juggler/releases/latest 2>/dev/null \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/^v//' || echo "")
  if [ -z "$VERSION" ]; then
    VERSION="2.2.0"
  fi
else
  VERSION="2.2.0"
fi

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# Show help message
show_help() {
  cat << EOF
RemoteJuggler Installation Script

USAGE:
    curl -fsSL <script-url> | sh
    sh install.sh [OPTIONS]

OPTIONS:
    --help              Show this help message
    --version VERSION   Install specific version (default: $VERSION)

ENVIRONMENT VARIABLES:
    REMOTE_JUGGLER_VERSION    Override default version

EXAMPLES:
    # Install latest version
    curl -fsSL https://gitlab.com/tinyland/projects/remote-juggler/-/raw/main/install.sh | sh

    # Install specific version
    REMOTE_JUGGLER_VERSION=2.1.0 sh install.sh

DESCRIPTION:
    This script performs the following operations:
    1. Detects platform (darwin/linux, amd64/arm64)
    2. Downloads binary from GitLab releases or GitHub
    3. Installs to ~/.local/bin (or first available in PATH)
    4. Initializes configuration at ~/.config/remote-juggler/config.json
    5. Imports identities from ~/.ssh/config
    6. Configures Claude Code slash commands

DOCUMENTATION:
    https://gitlab.com/tinyland/projects/remote-juggler

EOF
  exit 0
}

# Parse command-line arguments
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)
        show_help
        ;;
      --version)
        if [ -z "${2:-}" ]; then
          printf '%bError: --version requires a value%b\n' "$RED" "$NC" >&2
          exit 1
        fi
        VERSION="$2"
        shift
        ;;
      *)
        printf '%bUnknown option: %s%b\n' "$RED" "$1" "$NC" >&2
        printf 'Use --help for usage information\n' >&2
        exit 1
        ;;
    esac
    shift
  done
}

# Detect platform
detect_platform() {
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
      printf '%bUnsupported architecture: %s%b\n' "$RED" "$ARCH" "$NC" >&2
      exit 1
      ;;
  esac

  case "$OS" in
    darwin|linux) ;;
    *)
      printf '%bUnsupported operating system: %s%b\n' "$RED" "$OS" "$NC" >&2
      exit 1
      ;;
  esac

  PLATFORM="${OS}-${ARCH}"
}

# Print banner
print_banner() {
  printf '%b' "$BLUE"
  printf '==============================================================\n'
  printf '          RemoteJuggler Installer v%s\n' "$VERSION"
  printf '==============================================================\n'
  printf '%b' "$NC"
  printf 'Platform: %s\n' "$PLATFORM"
  printf '\n'
}

# Download binary from best available source
download_binary() {
  target="$1"
  artifact="${BINARY_NAME}-${PLATFORM}"
  tmp_file="${target}.tmp"

  printf 'Downloading %s...\n' "$artifact"

  # Try GitHub Releases first (primary distribution)
  if curl -fsSL "${GITHUB_REPO}/releases/download/v${VERSION}/${artifact}" -o "${tmp_file}" 2>/dev/null; then
    mv "${tmp_file}" "${target}"
    printf '%bDownloaded from GitHub%b\n' "$GREEN" "$NC"
    return 0
  fi

  # Fall back to GitLab releases
  if curl -fsSL "${GITLAB_REPO}/-/releases/v${VERSION}/downloads/${artifact}" -o "${tmp_file}" 2>/dev/null; then
    mv "${tmp_file}" "${target}"
    printf '%bDownloaded from GitLab releases%b\n' "$GREEN" "$NC"
    return 0
  fi

  # Fall back to GitLab Package Registry
  if curl -fsSL "${GITLAB_REPO}/-/package_files/generic/remote-juggler/${VERSION}/${artifact}" -o "${tmp_file}" 2>/dev/null; then
    mv "${tmp_file}" "${target}"
    printf '%bDownloaded from GitLab Package Registry%b\n' "$GREEN" "$NC"
    return 0
  fi

  # Clean up temp file if exists
  rm -f "${tmp_file}"
  return 1
}

# Find or create binary directory
install_binary() {
  target_dir=""

  # Check directories in order of preference
  for dir in "$HOME/.local/bin" "$HOME/bin" "$HOME/.bin"; do
    # Check if directory exists and is in PATH
    if [ -d "$dir" ] && printf '%s\n' "$PATH" | grep -q "\(^\|:\)$dir\(:\|\$\)"; then
      target_dir="$dir"
      break
    fi
  done

  # Create ~/.local/bin if none found
  if [ -z "$target_dir" ]; then
    target_dir="$HOME/.local/bin"
    mkdir -p "$target_dir"
    printf '%bCreated %s%b\n' "$YELLOW" "$target_dir" "$NC"
    printf '\n'
    printf '%bAdd to your PATH by adding this to your shell rc file:%b\n' "$YELLOW" "$NC"
    printf '  export PATH="$PATH:%s"\n' "$target_dir"
    printf '\n'
  fi

  printf 'Installing %s to %s...\n' "$BINARY_NAME" "$target_dir"

  if download_binary "${target_dir}/${BINARY_NAME}"; then
    chmod +x "${target_dir}/${BINARY_NAME}"
    printf '%bBinary installed successfully%b\n' "$GREEN" "$NC"
  else
    printf '%bFailed to download binary%b\n' "$RED" "$NC" >&2
    printf '\n' >&2
    printf 'You can try:\n' >&2
    printf '  1. Check your internet connection\n' >&2
    printf '  2. Verify the version exists: v%s\n' "$VERSION" >&2
    printf '  3. Build from source: make release\n' >&2
    exit 1
  fi

  # Export for later use
  INSTALLED_BINARY="${target_dir}/${BINARY_NAME}"
}

# Initialize configuration
init_config() {
  CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/remote-juggler"

  printf '\n'
  printf 'Initializing configuration...\n'

  mkdir -p "$CONFIG_DIR"

  if [ ! -f "${CONFIG_DIR}/config.json" ]; then
    # Try to use the binary to initialize config
    if "${INSTALLED_BINARY}" config init 2>/dev/null; then
      printf '%bConfiguration initialized at %s/config.json%b\n' "$GREEN" "$CONFIG_DIR" "$NC"
    else
      # Create minimal config manually
      cat > "${CONFIG_DIR}/config.json" << 'EOF'
{
  "$schema": "https://remote-juggler.dev/schema/v2.json",
  "version": "2.0.0",
  "identities": {},
  "settings": {
    "defaultProvider": "gitlab",
    "autoDetect": true,
    "useKeychain": true,
    "gpgSign": true,
    "fallbackToSSH": true,
    "verboseLogging": false
  },
  "state": {
    "currentIdentity": "",
    "lastSwitch": ""
  }
}
EOF
      printf '%bConfiguration created at %s/config.json%b\n' "$GREEN" "$CONFIG_DIR" "$NC"
    fi
  else
    printf '%bConfiguration already exists%b\n' "$GREEN" "$NC"
  fi

  # Import identities from SSH config
  printf 'Importing identities from ~/.ssh/config...\n'
  if "${INSTALLED_BINARY}" config import 2>/dev/null; then
    printf '%bSSH identities imported%b\n' "$GREEN" "$NC"
  else
    printf '%bSSH import skipped (run "remote-juggler config import" manually)%b\n' "$YELLOW" "$NC"
  fi

  # Sync managed blocks
  if "${INSTALLED_BINARY}" config sync 2>/dev/null; then
    printf '%bManaged blocks synchronized%b\n' "$GREEN" "$NC"
  fi
}

# Configure Claude Code integration
configure_claude() {
  config_dir="$1"

  printf '  Configuring Claude Code...\n'

  mkdir -p "${config_dir}/commands"
  mkdir -p "${config_dir}/skills/git-identity"

  # Download slash commands
  commands_url="${GITLAB_REPO}/-/raw/main/.claude/commands"

  for cmd in juggle identity remotes; do
    if curl -fsSL "${commands_url}/${cmd}.md" -o "${config_dir}/commands/${cmd}.md" 2>/dev/null; then
      printf '    %b/%s command installed%b\n' "$GREEN" "$cmd" "$NC"
    else
      # Create from embedded content
      case "$cmd" in
        juggle)
          cat > "${config_dir}/commands/${cmd}.md" << 'EOF'
---
description: Switch git identity context using RemoteJuggler
allowed-tools: "Bash(...), Read(...)"
---

Switch to the requested git identity context.

Arguments: $ARGUMENTS (identity name like "personal", "work", "github-personal")

Steps:
1. Run `remote-juggler detect` to show current identity
2. Run `remote-juggler switch $ARGUMENTS` to switch
3. Verify the switch with `remote-juggler status`
EOF
          printf '    %b/%s command created%b\n' "$GREEN" "$cmd" "$NC"
          ;;
        identity)
          cat > "${config_dir}/commands/${cmd}.md" << 'EOF'
---
description: Show or manage git identities with RemoteJuggler
allowed-tools: "Bash(...), Read(...)"
---

Manage git identities across GitLab and GitHub.

Usage:
- /identity list - List all configured identities
- /identity detect - Detect current repository's identity
- /identity validate <name> - Validate an identity's connectivity

Run the appropriate remote-juggler command based on $ARGUMENTS.
EOF
          printf '    %b/%s command created%b\n' "$GREEN" "$cmd" "$NC"
          ;;
        remotes)
          cat > "${config_dir}/commands/${cmd}.md" << 'EOF'
---
description: Manage git remotes with identity awareness
allowed-tools: "Bash(...), Read(...)"
---

View and manage git remotes with identity context.

Run `remote-juggler detect` to identify the current remote configuration
and suggest appropriate identity switches if needed.
EOF
          printf '    %b/%s command created%b\n' "$GREEN" "$cmd" "$NC"
          ;;
      esac
    fi
  done

  # Download skill
  skill_url="${GITLAB_REPO}/-/raw/main/.claude/skills/git-identity/SKILL.md"
  if curl -fsSL "${skill_url}" -o "${config_dir}/skills/git-identity/SKILL.md" 2>/dev/null; then
    printf '    %bgit-identity skill installed%b\n' "$GREEN" "$NC"
  else
    cat > "${config_dir}/skills/git-identity/SKILL.md" << 'EOF'
---
name: "git-identity"
description: "Automatically manages git identity switching across GitLab and GitHub accounts."
allowed-tools: "Read(...), Bash(...)"
---

## Git Identity Management with RemoteJuggler

This skill helps manage multiple git identities seamlessly.

### When to activate:
- User mentions switching git accounts or identities
- Git push/pull fails with authentication errors
- Working with repositories from different organizations
- GPG signing issues or verification failures

### Available commands:
- `remote-juggler status` - Current identity and repository info
- `remote-juggler list` - All configured identities
- `remote-juggler detect` - Auto-detect appropriate identity
- `remote-juggler switch <name>` - Switch to identity
- `remote-juggler validate <name>` - Test SSH/API connectivity
EOF
    printf '    %bgit-identity skill created%b\n' "$GREEN" "$NC"
  fi

  printf '  %bClaude Code integration configured%b\n' "$GREEN" "$NC"
}

# Configure JetBrains integration
configure_jetbrains() {
  config_dir="$1"

  printf '  Configuring JetBrains ACP...\n'

  mkdir -p "$config_dir"

  if [ -f "${config_dir}/acp.json" ]; then
    printf '    %bExisting acp.json found - checking for RemoteJuggler entry%b\n' "$YELLOW" "$NC"

    # Check if RemoteJuggler is already configured
    if grep -q "RemoteJuggler" "${config_dir}/acp.json" 2>/dev/null; then
      printf '    %bRemoteJuggler already configured%b\n' "$GREEN" "$NC"
    else
      printf '    %bAdd RemoteJuggler manually to %s/acp.json:%b\n' "$YELLOW" "$config_dir" "$NC"
      printf '    "RemoteJuggler": {\n'
      printf '      "command": "remote-juggler",\n'
      printf '      "args": ["--mode=acp"],\n'
      printf '      "env": {},\n'
      printf '      "use_idea_mcp": false,\n'
      printf '      "use_custom_mcp": false\n'
      printf '    }\n'
    fi
  else
    # Create new acp.json
    cat > "${config_dir}/acp.json" << 'EOF'
{
  "agent_servers": {
    "RemoteJuggler": {
      "command": "remote-juggler",
      "args": ["--mode=acp"],
      "env": {},
      "use_idea_mcp": false,
      "use_custom_mcp": false
    }
  }
}
EOF
    printf '  %bJetBrains ACP integration configured%b\n' "$GREEN" "$NC"
  fi
}

# Configure Cursor MCP
configure_cursor() {
  cursor_dir="$HOME/.cursor"
  mcp_file="${cursor_dir}/mcp.json"

  if [ ! -d "$cursor_dir" ]; then
    return 0  # Cursor not installed
  fi

  printf '  Configuring Cursor MCP...\n'

  if [ -f "$mcp_file" ]; then
    # Check if already configured
    if grep -q "remote-juggler" "$mcp_file" 2>/dev/null; then
      printf '    Already configured\n'
      return 0
    fi
  fi

  # Write MCP config (simple case - create or overwrite)
  mkdir -p "$cursor_dir"
  cat > "$mcp_file" << 'EOF'
{
  "mcpServers": {
    "remote-juggler": {
      "command": "remote-juggler",
      "args": ["--mode=mcp"]
    }
  }
}
EOF
  printf '    %bConfigured%b: %s\n' "$GREEN" "$NC" "$mcp_file"
}

# Configure VS Code MCP
configure_vscode() {
  if [ "$OS" = "darwin" ]; then
    vscode_dir="$HOME/Library/Application Support/Code/User"
  else
    vscode_dir="$HOME/.config/Code/User"
  fi

  if [ ! -d "$vscode_dir" ]; then
    return 0  # VS Code not installed
  fi

  printf '  Configuring VS Code MCP...\n'

  mcp_file="${vscode_dir}/mcp.json"

  if [ -f "$mcp_file" ] && grep -q "remote-juggler" "$mcp_file" 2>/dev/null; then
    printf '    Already configured\n'
    return 0
  fi

  # Write MCP config
  cat > "$mcp_file" << 'EOF'
{
  "servers": {
    "remote-juggler": {
      "command": "remote-juggler",
      "args": ["--mode=mcp"]
    }
  }
}
EOF
  printf '    %bConfigured%b: %s\n' "$GREEN" "$NC" "$mcp_file"
}

# Configure Windsurf MCP
configure_windsurf() {
  windsurf_dir="$HOME/.windsurf"
  mcp_file="${windsurf_dir}/mcp.json"

  if [ ! -d "$windsurf_dir" ]; then
    return 0  # Windsurf not installed
  fi

  printf '  Configuring Windsurf MCP...\n'

  if [ -f "$mcp_file" ] && grep -q "remote-juggler" "$mcp_file" 2>/dev/null; then
    printf '    Already configured\n'
    return 0
  fi

  mkdir -p "$windsurf_dir"
  cat > "$mcp_file" << 'EOF'
{
  "mcpServers": {
    "remote-juggler": {
      "command": "remote-juggler",
      "args": ["--mode=mcp"]
    }
  }
}
EOF
  printf '    %bConfigured%b: %s\n' "$GREEN" "$NC" "$mcp_file"
}

# Configure IDE integrations
configure_ides() {
  printf '\n'
  printf 'Configuring IDE/agent integrations...\n'

  # Always configure Claude Code (create dirs if needed)
  configure_claude "$HOME/.claude"

  # Configure JetBrains if directory exists
  if [ -d "$HOME/.jetbrains" ] || [ -d "$HOME/Library/Application Support/JetBrains" ]; then
    configure_jetbrains "$HOME/.jetbrains"
  fi

  # Configure MCP clients (if installed)
  configure_cursor
  configure_vscode
  configure_windsurf

  printf '\n'
  printf '%bMCP Server:%b remote-juggler --mode=mcp\n' "$BLUE" "$NC"
  printf '  Works with: Claude Code, Cursor, VS Code, Windsurf, and any MCP client\n'
}

# Setup Darwin keychain (if applicable)
setup_keychain() {
  if [ "$OS" = "darwin" ]; then
    printf '\n'
    printf '%bDarwin Keychain Integration%b\n' "$BLUE" "$NC"
    printf '  macOS detected - secure keychain storage enabled\n'
    printf '\n'
    printf '  Store tokens securely:\n'
    printf '    %s token set personal\n' "$BINARY_NAME"
    printf '    %s token set work\n' "$BINARY_NAME"
    printf '\n'
    printf '  Tokens are stored in macOS Keychain with service name:\n'
    printf '    remote-juggler.<provider>.<identity>\n'
  fi
}

# Print completion message
print_completion() {
  printf '\n'
  printf '%b==============================================================\n' "$GREEN"
  printf '          Installation Complete!\n'
  printf '==============================================================%b\n' "$NC"
  printf '\n'
  printf 'Quick start:\n'
  printf '  %s list              # List configured identities\n' "$BINARY_NAME"
  printf '  %s detect            # Detect current repo identity\n' "$BINARY_NAME"
  printf '  %s switch <identity> # Switch identity\n' "$BINARY_NAME"
  printf '\n'
  printf 'Configuration:\n'
  printf '  %s config show       # View current configuration\n' "$BINARY_NAME"
  printf '  %s config add <name> # Add new identity\n' "$BINARY_NAME"
  printf '  %s config import     # Import from SSH config\n' "$BINARY_NAME"
  printf '\n'
  printf 'Credential management:\n'
  printf '  %s token set <id>    # Store in keychain (Darwin)\n' "$BINARY_NAME"
  printf '  %s token verify      # Test all credentials\n' "$BINARY_NAME"
  printf '\n'
  printf 'Server modes (for AI agents):\n'
  printf '  %s --mode=mcp        # Claude Code, VS Code, Cursor\n' "$BINARY_NAME"
  printf '  %s --mode=acp        # JetBrains IDEs\n' "$BINARY_NAME"
  printf '\n'
  printf 'Documentation:\n'
  printf '  %s\n' "$GITLAB_REPO"
  printf '\n'
}

# Cleanup on error
cleanup() {
  if [ -n "${tmp_file:-}" ] && [ -f "${tmp_file}" ]; then
    rm -f "${tmp_file}"
  fi
}
trap cleanup EXIT INT TERM

# Main installation
main() {
  parse_args "$@"
  detect_platform
  print_banner
  install_binary
  init_config
  configure_ides
  setup_keychain
  print_completion
}

main "$@"
