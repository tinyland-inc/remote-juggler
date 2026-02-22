#!/usr/bin/env bash
#
# RemoteJuggler Universal Installer
#
# Usage:
#   curl -fsSL https://get.remote-juggler.dev | bash
#   curl -fsSL https://get.remote-juggler.dev | bash -s -- --version 2.0.0
#
# Options:
#   --version VERSION    Install specific version (default: latest)
#   --prefix PATH        Installation prefix (default: ~/.local)
#   --no-verify          Skip GPG signature verification
#   --channel CHANNEL    Release channel: stable, beta, nightly (default: stable)
#   --help               Show this help message
#
# Environment:
#   REMOTE_JUGGLER_PREFIX    Override installation prefix
#   REMOTE_JUGGLER_VERSION   Override version to install
#   REMOTE_JUGGLER_CHANNEL   Override release channel
#
set -euo pipefail

# Configuration
REPO_URL="https://github.com/tinyland-inc/remote-juggler"
RELEASES_URL="${REPO_URL}/releases"
GPG_KEY_URL="${REPO_URL}/raw/main/keys/release-signing.asc"
DEFAULT_PREFIX="${HOME}/.local"
PROGRAM_NAME="remote-juggler"

# Colors (if terminal supports them)
if [[ -t 1 ]] && [[ -n "${TERM:-}" ]] && command -v tput &>/dev/null; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    RESET=""
fi

# Logging functions
info() { echo "${BLUE}==>${RESET} $*"; }
success() { echo "${GREEN}==>${RESET} $*"; }
warn() { echo "${YELLOW}Warning:${RESET} $*" >&2; }
error() { echo "${RED}Error:${RESET} $*" >&2; }
die() { error "$*"; exit 1; }

# Print usage
usage() {
    cat <<EOF
${BOLD}RemoteJuggler Universal Installer${RESET}

Usage:
  $0 [options]

Options:
  --version VERSION    Install specific version (default: latest)
  --prefix PATH        Installation prefix (default: ~/.local)
  --no-verify          Skip GPG signature verification
  --channel CHANNEL    Release channel: stable, beta, nightly (default: stable)
  --uninstall          Remove RemoteJuggler installation
  --help               Show this help message

Examples:
  # Install latest stable release
  curl -fsSL https://get.remote-juggler.dev | bash

  # Install specific version
  curl -fsSL https://get.remote-juggler.dev | bash -s -- --version 2.0.0

  # Install to /usr/local (requires sudo)
  curl -fsSL https://get.remote-juggler.dev | sudo bash -s -- --prefix /usr/local

  # Uninstall
  curl -fsSL https://get.remote-juggler.dev | bash -s -- --uninstall
EOF
}

# Detect OS and architecture
detect_platform() {
    local os arch

    # Detect OS
    case "$(uname -s)" in
        Linux*)  os="linux" ;;
        Darwin*) os="darwin" ;;
        MINGW*|MSYS*|CYGWIN*) os="windows" ;;
        *)       die "Unsupported operating system: $(uname -s)" ;;
    esac

    # Detect architecture
    case "$(uname -m)" in
        x86_64|amd64)   arch="amd64" ;;
        aarch64|arm64)  arch="arm64" ;;
        armv7l)         arch="armv7" ;;
        *)              die "Unsupported architecture: $(uname -m)" ;;
    esac

    echo "${os}-${arch}"
}

# Check for required commands
check_dependencies() {
    local missing=()

    for cmd in curl tar; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required commands: ${missing[*]}"
    fi

    # Check for GPG if verification is enabled
    if [[ "${VERIFY:-true}" == "true" ]] && ! command -v gpg &>/dev/null; then
        warn "GPG not found. Skipping signature verification."
        warn "Install GPG for enhanced security: brew install gnupg (macOS) or apt install gnupg (Linux)"
        VERIFY="false"
    fi
}

# Get latest version from GitLab API
get_latest_version() {
    local channel="${1:-stable}"
    local api_url="https://api.github.com/repos/tinyland-inc/remote-juggler/releases"

    # Fetch releases
    local releases
    releases=$(curl -fsSL "$api_url" 2>/dev/null) || die "Failed to fetch releases"

    # Parse latest version based on channel
    local version
    case "$channel" in
        stable)
            # Stable releases: no pre-release suffix
            version=$(echo "$releases" | grep -o '"tag_name":"v[0-9.]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
            ;;
        beta)
            # Beta releases: -beta or -rc suffix
            version=$(echo "$releases" | grep -o '"tag_name":"v[0-9.]*-\(beta\|rc\)[0-9]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
            ;;
        nightly)
            # Nightly: use latest tag regardless
            version=$(echo "$releases" | grep -o '"tag_name":"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/^v//')
            ;;
        *)
            die "Unknown channel: $channel. Use: stable, beta, nightly"
            ;;
    esac

    if [[ -z "$version" ]]; then
        die "No ${channel} release found"
    fi

    echo "$version"
}

# Download file with progress
download() {
    local url="$1"
    local output="$2"

    info "Downloading: $(basename "$output")"

    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$output" "$url" || return 1
    else
        curl -fSL --progress-bar -o "$output" "$url" || return 1
    fi
}

# Verify GPG signature
verify_signature() {
    local archive="$1"
    local signature="${archive}.asc"
    local checksums="$2"

    if [[ "${VERIFY}" != "true" ]]; then
        warn "Skipping signature verification (--no-verify)"
        return 0
    fi

    info "Verifying GPG signature..."

    # Import release signing key
    local keyring
    keyring=$(mktemp)
    trap "rm -f '$keyring'" RETURN

    if ! curl -fsSL "$GPG_KEY_URL" | gpg --dearmor > "$keyring" 2>/dev/null; then
        warn "Could not fetch GPG signing key. Skipping verification."
        return 0
    fi

    # Verify checksums signature
    if [[ -f "${checksums}.asc" ]]; then
        if gpg --no-default-keyring --keyring "$keyring" --verify "${checksums}.asc" "$checksums" 2>/dev/null; then
            success "Checksum file signature verified"
        else
            warn "Checksum signature verification failed"
        fi
    fi

    # Verify checksum
    local expected_hash
    expected_hash=$(grep "$(basename "$archive")" "$checksums" | awk '{print $1}')

    if [[ -n "$expected_hash" ]]; then
        local actual_hash
        if command -v sha256sum &>/dev/null; then
            actual_hash=$(sha256sum "$archive" | awk '{print $1}')
        elif command -v shasum &>/dev/null; then
            actual_hash=$(shasum -a 256 "$archive" | awk '{print $1}')
        else
            warn "No SHA256 tool found. Skipping checksum verification."
            return 0
        fi

        if [[ "$expected_hash" == "$actual_hash" ]]; then
            success "Checksum verified: ${actual_hash:0:16}..."
        else
            die "Checksum mismatch! Expected: $expected_hash, Got: $actual_hash"
        fi
    fi
}

# Install binary
install_binary() {
    local archive="$1"
    local prefix="$2"
    local bindir="${prefix}/bin"

    info "Installing to ${bindir}..."

    # Create directories
    mkdir -p "$bindir"

    # Extract archive
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" RETURN

    tar -xzf "$archive" -C "$tmpdir"

    # Find and install binary
    local binary
    binary=$(find "$tmpdir" -name "${PROGRAM_NAME}" -type f | head -1)

    if [[ -z "$binary" ]]; then
        die "Binary not found in archive"
    fi

    # Install binary
    install -m 755 "$binary" "${bindir}/${PROGRAM_NAME}"

    # Install shell completions if available
    local completions_dir="${prefix}/share/${PROGRAM_NAME}/completions"
    mkdir -p "$completions_dir"

    for shell in bash zsh fish; do
        local completion
        completion=$(find "$tmpdir" -name "*${shell}*" -o -name "*.${shell}" | head -1)
        if [[ -n "$completion" ]]; then
            install -m 644 "$completion" "${completions_dir}/"
        fi
    done

    success "Installed ${PROGRAM_NAME} to ${bindir}/${PROGRAM_NAME}"
}

# Install shell completions to standard locations
install_completions() {
    local prefix="$1"
    local completions_src="${prefix}/share/${PROGRAM_NAME}/completions"

    if [[ ! -d "$completions_src" ]]; then
        return 0
    fi

    # Bash completions
    local bash_dir="${HOME}/.local/share/bash-completion/completions"
    if [[ -d "${bash_dir%/*}" ]] || mkdir -p "$bash_dir"; then
        if [[ -f "${completions_src}/${PROGRAM_NAME}.bash" ]]; then
            ln -sf "${completions_src}/${PROGRAM_NAME}.bash" "${bash_dir}/${PROGRAM_NAME}"
        fi
    fi

    # Zsh completions
    local zsh_dir="${HOME}/.zsh/completions"
    if [[ -d "$zsh_dir" ]] || mkdir -p "$zsh_dir"; then
        if [[ -f "${completions_src}/_${PROGRAM_NAME}" ]]; then
            ln -sf "${completions_src}/_${PROGRAM_NAME}" "${zsh_dir}/_${PROGRAM_NAME}"
        fi
    fi

    # Fish completions
    local fish_dir="${HOME}/.config/fish/completions"
    if [[ -d "${fish_dir%/*}" ]] || mkdir -p "$fish_dir"; then
        if [[ -f "${completions_src}/${PROGRAM_NAME}.fish" ]]; then
            ln -sf "${completions_src}/${PROGRAM_NAME}.fish" "${fish_dir}/${PROGRAM_NAME}.fish"
        fi
    fi
}

# Post-install setup
post_install() {
    local prefix="$1"
    local bindir="${prefix}/bin"

    # Check if bindir is in PATH
    if [[ ":${PATH}:" != *":${bindir}:"* ]]; then
        warn "${bindir} is not in your PATH"
        echo ""
        echo "Add to your shell profile:"
        echo ""
        echo "  # For bash (~/.bashrc)"
        echo "  export PATH=\"${bindir}:\$PATH\""
        echo ""
        echo "  # For zsh (~/.zshrc)"
        echo "  export PATH=\"${bindir}:\$PATH\""
        echo ""
        echo "  # For fish (~/.config/fish/config.fish)"
        echo "  fish_add_path ${bindir}"
        echo ""
    fi

    # Run setup wizard suggestion
    echo ""
    success "Installation complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Restart your shell or run: source ~/.bashrc (or ~/.zshrc)"
    echo "  2. Run the setup wizard: ${PROGRAM_NAME} setup"
    echo "  3. List identities: ${PROGRAM_NAME} list"
    echo ""
    echo "Documentation: https://remote-juggler.dev/docs"
    echo "Report issues: ${REPO_URL}/issues"
}

# Uninstall
uninstall() {
    local prefix="${1:-$DEFAULT_PREFIX}"
    local bindir="${prefix}/bin"

    info "Uninstalling RemoteJuggler..."

    # Remove binary
    if [[ -f "${bindir}/${PROGRAM_NAME}" ]]; then
        rm -f "${bindir}/${PROGRAM_NAME}"
        success "Removed ${bindir}/${PROGRAM_NAME}"
    fi

    # Remove completions directory
    local share_dir="${prefix}/share/${PROGRAM_NAME}"
    if [[ -d "$share_dir" ]]; then
        rm -rf "$share_dir"
        success "Removed ${share_dir}"
    fi

    # Remove completion symlinks
    rm -f "${HOME}/.local/share/bash-completion/completions/${PROGRAM_NAME}" 2>/dev/null || true
    rm -f "${HOME}/.zsh/completions/_${PROGRAM_NAME}" 2>/dev/null || true
    rm -f "${HOME}/.config/fish/completions/${PROGRAM_NAME}.fish" 2>/dev/null || true

    echo ""
    success "Uninstall complete!"
    echo ""
    echo "Note: User configuration preserved at ~/.config/remote-juggler/"
    echo "To remove configuration: rm -rf ~/.config/remote-juggler"
}

# Main installation flow
main() {
    local version=""
    local prefix="${REMOTE_JUGGLER_PREFIX:-$DEFAULT_PREFIX}"
    local channel="${REMOTE_JUGGLER_CHANNEL:-stable}"
    local do_uninstall="false"
    VERIFY="true"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                version="$2"
                shift 2
                ;;
            --prefix)
                prefix="$2"
                shift 2
                ;;
            --channel)
                channel="$2"
                shift 2
                ;;
            --no-verify)
                VERIFY="false"
                shift
                ;;
            --uninstall)
                do_uninstall="true"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    # Handle uninstall
    if [[ "$do_uninstall" == "true" ]]; then
        uninstall "$prefix"
        exit 0
    fi

    echo "${BOLD}RemoteJuggler Installer${RESET}"
    echo ""

    # Check dependencies
    check_dependencies

    # Detect platform
    local platform
    platform=$(detect_platform)
    info "Detected platform: ${platform}"

    # Get version
    if [[ -z "$version" ]]; then
        version="${REMOTE_JUGGLER_VERSION:-}"
    fi
    if [[ -z "$version" ]]; then
        info "Fetching latest ${channel} version..."
        version=$(get_latest_version "$channel")
    fi
    info "Installing version: ${version}"

    # Construct download URL
    local archive_name="${PROGRAM_NAME}-${version}-${platform}.tar.gz"
    local archive_url="${REPO_URL}/releases/download/v${version}/${archive_name}"
    local checksums_url="${REPO_URL}/releases/download/v${version}/SHA256SUMS.txt"

    # Create temp directory
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT

    # Download archive
    local archive="${tmpdir}/${archive_name}"
    download "$archive_url" "$archive" || die "Failed to download ${archive_name}"

    # Download and verify checksums
    local checksums="${tmpdir}/SHA256SUMS.txt"
    if download "$checksums_url" "$checksums" 2>/dev/null; then
        # Try to get signature
        download "${checksums_url}.asc" "${checksums}.asc" 2>/dev/null || true
        verify_signature "$archive" "$checksums"
    else
        warn "Could not download checksums. Skipping verification."
    fi

    # Install
    install_binary "$archive" "$prefix"
    install_completions "$prefix"
    post_install "$prefix"
}

# Run main
main "$@"
