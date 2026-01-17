#!/bin/bash
# RemoteJuggler - Rootless Installation Script
# https://gitlab.com/tinyland/projects/remote-juggler
#
# Usage:
#   curl -fsSL https://gitlab.com/tinyland/projects/remote-juggler/-/raw/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Jesssullivan/remote-juggler/main/install.sh | bash

set -euo pipefail

# Configuration
GITLAB_REPO="https://gitlab.com/tinyland/projects/remote-juggler"
GITHUB_REPO="https://github.com/Jesssullivan/remote-juggler"
BINARY_NAME="remote-juggler"
VERSION="${REMOTE_JUGGLER_VERSION:-2.0.0}"

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
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

# Detect platform
detect_platform() {
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
      echo -e "${RED}Unsupported architecture: $ARCH${NC}"
      exit 1
      ;;
  esac

  case "$OS" in
    darwin|linux) ;;
    *)
      echo -e "${RED}Unsupported operating system: $OS${NC}"
      exit 1
      ;;
  esac

  PLATFORM="${OS}-${ARCH}"
}

# Binary installation paths (in order of preference)
BIN_PATHS=(
  "$HOME/.local/bin"
  "$HOME/bin"
  "$HOME/.bin"
)

# Config location (XDG Base Directory Specification)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/remote-juggler"

# IDE config locations
declare -A IDE_CONFIGS=(
  ["claude"]="$HOME/.claude"
  ["jetbrains"]="$HOME/.jetbrains"
)

# Print banner
print_banner() {
  echo -e "${BLUE}"
  echo "=============================================================="
  echo "          RemoteJuggler Installer v${VERSION}"
  echo "=============================================================="
  echo -e "${NC}"
  echo "Platform: ${PLATFORM}"
  echo ""
}

# Download binary from best available source
download_binary() {
  local target="$1"
  local artifact="${BINARY_NAME}-${PLATFORM}"
  local tmp_file="${target}.tmp"

  echo "Downloading ${artifact}..."

  # Try GitLab Generic Packages first
  if curl -fsSL "${GITLAB_REPO}/-/releases/v${VERSION}/downloads/${artifact}" -o "${tmp_file}" 2>/dev/null; then
    mv "${tmp_file}" "${target}"
    echo -e "${GREEN}Downloaded from GitLab${NC}"
    return 0
  fi

  # Try GitLab Package Registry
  if curl -fsSL "${GITLAB_REPO}/-/package_files/generic/remote-juggler/${VERSION}/${artifact}" -o "${tmp_file}" 2>/dev/null; then
    mv "${tmp_file}" "${target}"
    echo -e "${GREEN}Downloaded from GitLab Package Registry${NC}"
    return 0
  fi

  # Fall back to GitHub Releases
  if curl -fsSL "${GITHUB_REPO}/releases/download/v${VERSION}/${artifact}" -o "${tmp_file}" 2>/dev/null; then
    mv "${tmp_file}" "${target}"
    echo -e "${GREEN}Downloaded from GitHub${NC}"
    return 0
  fi

  # Clean up temp file if exists
  rm -f "${tmp_file}"
  return 1
}

# Find or create binary directory
install_binary() {
  local target_dir=""

  # Find existing directory in PATH
  for dir in "${BIN_PATHS[@]}"; do
    if [[ -d "$dir" && ":$PATH:" == *":$dir:"* ]]; then
      target_dir="$dir"
      break
    fi
  done

  # Create first preference if none found
  if [[ -z "$target_dir" ]]; then
    target_dir="${BIN_PATHS[0]}"
    mkdir -p "$target_dir"
    echo -e "${YELLOW}Created ${target_dir}${NC}"
    echo ""
    echo -e "${YELLOW}Add to your PATH by adding this to your shell rc file:${NC}"
    echo "  export PATH=\"\$PATH:${target_dir}\""
    echo ""
  fi

  echo "Installing ${BINARY_NAME} to ${target_dir}..."

  if download_binary "${target_dir}/${BINARY_NAME}"; then
    chmod +x "${target_dir}/${BINARY_NAME}"
    echo -e "${GREEN}Binary installed successfully${NC}"
  else
    echo -e "${RED}Failed to download binary${NC}"
    echo ""
    echo "You can try:"
    echo "  1. Check your internet connection"
    echo "  2. Verify the version exists: v${VERSION}"
    echo "  3. Build from source: mason build --release"
    exit 1
  fi

  # Export for later use
  INSTALLED_BINARY="${target_dir}/${BINARY_NAME}"
}

# Initialize configuration
init_config() {
  echo ""
  echo "Initializing configuration..."

  mkdir -p "${CONFIG_DIR}"

  if [[ ! -f "${CONFIG_DIR}/config.json" ]]; then
    # Create initial config using the binary
    if "${INSTALLED_BINARY}" config init 2>/dev/null; then
      echo -e "${GREEN}Configuration initialized at ${CONFIG_DIR}/config.json${NC}"
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
      echo -e "${GREEN}Configuration created at ${CONFIG_DIR}/config.json${NC}"
    fi
  else
    echo -e "${GREEN}Configuration already exists${NC}"
  fi

  # Import identities from SSH config
  echo "Importing identities from ~/.ssh/config..."
  if "${INSTALLED_BINARY}" config import 2>/dev/null; then
    echo -e "${GREEN}SSH identities imported${NC}"
  else
    echo -e "${YELLOW}SSH import skipped (run 'remote-juggler config import' manually)${NC}"
  fi

  # Sync managed blocks
  if "${INSTALLED_BINARY}" config sync 2>/dev/null; then
    echo -e "${GREEN}Managed blocks synchronized${NC}"
  fi
}

# Configure Claude Code integration
configure_claude() {
  local config_dir="$1"

  echo "  Configuring Claude Code..."

  mkdir -p "${config_dir}/commands"
  mkdir -p "${config_dir}/skills/git-identity"

  # Download slash commands
  local commands_url="${GITLAB_REPO}/-/raw/main/.claude/commands"

  for cmd in juggle identity remotes; do
    if curl -fsSL "${commands_url}/${cmd}.md" -o "${config_dir}/commands/${cmd}.md" 2>/dev/null; then
      echo -e "    ${GREEN}/${cmd} command installed${NC}"
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
          echo -e "    ${GREEN}/${cmd} command created${NC}"
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
          echo -e "    ${GREEN}/${cmd} command created${NC}"
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
          echo -e "    ${GREEN}/${cmd} command created${NC}"
          ;;
      esac
    fi
  done

  # Download skill
  local skill_url="${GITLAB_REPO}/-/raw/main/.claude/skills/git-identity/SKILL.md"
  if curl -fsSL "${skill_url}" -o "${config_dir}/skills/git-identity/SKILL.md" 2>/dev/null; then
    echo -e "    ${GREEN}git-identity skill installed${NC}"
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
    echo -e "    ${GREEN}git-identity skill created${NC}"
  fi

  echo -e "  ${GREEN}Claude Code integration configured${NC}"
}

# Configure JetBrains integration
configure_jetbrains() {
  local config_dir="$1"

  echo "  Configuring JetBrains ACP..."

  mkdir -p "${config_dir}"

  if [[ -f "${config_dir}/acp.json" ]]; then
    echo -e "    ${YELLOW}Existing acp.json found - checking for RemoteJuggler entry${NC}"

    # Check if RemoteJuggler is already configured
    if grep -q "RemoteJuggler" "${config_dir}/acp.json" 2>/dev/null; then
      echo -e "    ${GREEN}RemoteJuggler already configured${NC}"
    else
      echo -e "    ${YELLOW}Add RemoteJuggler manually to ${config_dir}/acp.json:${NC}"
      echo '    "RemoteJuggler": {'
      echo '      "command": "remote-juggler",'
      echo '      "args": ["--mode=acp"],'
      echo '      "env": {},'
      echo '      "use_idea_mcp": false,'
      echo '      "use_custom_mcp": false'
      echo '    }'
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
    echo -e "  ${GREEN}JetBrains ACP integration configured${NC}"
  fi
}

# Configure IDE integrations
configure_ides() {
  echo ""
  echo "Configuring IDE integrations..."

  # Always configure Claude Code (create dirs if needed)
  configure_claude "${IDE_CONFIGS[claude]}"

  # Configure JetBrains if directory exists or user has IntelliJ
  if [[ -d "${IDE_CONFIGS[jetbrains]}" ]] || [[ -d "$HOME/Library/Application Support/JetBrains" ]]; then
    configure_jetbrains "${IDE_CONFIGS[jetbrains]}"
  fi

  # Note about project-level configs
  echo ""
  echo -e "${BLUE}Project-level configuration:${NC}"
  echo "  For MCP-enabled editors (VS Code, Cursor, etc.):"
  echo "  Copy .mcp.json to your project root:"
  echo ""
  echo '  {
    "mcpServers": {
      "remote-juggler": {
        "command": "remote-juggler",
        "args": ["--mode=mcp"]
      }
    }
  }'
}

# Setup Darwin keychain (if applicable)
setup_keychain() {
  if [[ "$OS" == "darwin" ]]; then
    echo ""
    echo -e "${BLUE}Darwin Keychain Integration${NC}"
    echo "  macOS detected - secure keychain storage enabled"
    echo ""
    echo "  Store tokens securely:"
    echo "    ${BINARY_NAME} token set personal"
    echo "    ${BINARY_NAME} token set work"
    echo ""
    echo "  Tokens are stored in macOS Keychain with service name:"
    echo "    remote-juggler.<provider>.<identity>"
  fi
}

# Print completion message
print_completion() {
  echo ""
  echo -e "${GREEN}=============================================================="
  echo "          Installation Complete!"
  echo "==============================================================${NC}"
  echo ""
  echo "Quick start:"
  echo "  ${BINARY_NAME} list              # List configured identities"
  echo "  ${BINARY_NAME} detect            # Detect current repo identity"
  echo "  ${BINARY_NAME} switch <identity> # Switch identity"
  echo ""
  echo "Configuration:"
  echo "  ${BINARY_NAME} config show       # View current configuration"
  echo "  ${BINARY_NAME} config add <name> # Add new identity"
  echo "  ${BINARY_NAME} config import     # Import from SSH config"
  echo ""
  echo "Credential management:"
  echo "  ${BINARY_NAME} token set <id>    # Store in keychain (Darwin)"
  echo "  ${BINARY_NAME} token verify      # Test all credentials"
  echo ""
  echo "Server modes (for AI agents):"
  echo "  ${BINARY_NAME} --mode=mcp        # Claude Code, VS Code, Cursor"
  echo "  ${BINARY_NAME} --mode=acp        # JetBrains IDEs"
  echo ""
  echo "Documentation:"
  echo "  ${GITLAB_REPO}"
  echo ""
}

# Cleanup on error
cleanup() {
  if [[ -n "${tmp_file:-}" && -f "${tmp_file}" ]]; then
    rm -f "${tmp_file}"
  fi
}
trap cleanup EXIT

# Main installation
main() {
  detect_platform
  print_banner
  install_binary
  init_config
  configure_ides
  setup_keychain
  print_completion
}

main "$@"
