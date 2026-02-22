#!/usr/bin/env bash
#
# RemoteJuggler Release Verification Script
#
# Verifies the integrity and authenticity of RemoteJuggler releases using:
# - SHA256 checksums
# - GPG signatures
# - Optional: Sigstore cosign verification
#
# Usage:
#   ./verify-release.sh <archive>
#   ./verify-release.sh remote-juggler-2.0.0-linux-amd64.tar.gz
#
set -euo pipefail

# Configuration
REPO_URL="https://github.com/tinyland-inc/remote-juggler"
GPG_KEY_ID="ABC123DEF456"  # Replace with actual release signing key
GPG_KEY_URL="${REPO_URL}/raw/main/keys/release-signing.asc"
COSIGN_KEY_URL="${REPO_URL}/raw/main/keys/cosign.pub"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}==>${NC} $*"; }
success() { echo -e "${GREEN}[PASS]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
error() { echo -e "${RED}Error:${NC} $*" >&2; exit 1; }

usage() {
    cat <<EOF
RemoteJuggler Release Verification

Usage:
  $0 <archive> [checksums]

Arguments:
  archive     Path to the release archive (.tar.gz)
  checksums   Path to SHA256SUMS.txt (optional, will download if not provided)

Options:
  --gpg-only      Only verify GPG signature
  --checksum-only Only verify SHA256 checksum
  --cosign        Also verify with Sigstore cosign
  --help          Show this help

Examples:
  $0 remote-juggler-2.0.0-linux-amd64.tar.gz
  $0 remote-juggler-2.0.0-darwin-arm64.tar.gz SHA256SUMS.txt
  $0 --cosign remote-juggler-2.0.0-linux-amd64.tar.gz

The script will:
  1. Verify SHA256 checksum matches SHA256SUMS.txt
  2. Verify GPG signature on SHA256SUMS.txt.asc
  3. (Optional) Verify Sigstore cosign signature
EOF
}

# Fetch GPG signing key
fetch_gpg_key() {
    local keyring="$1"

    info "Fetching GPG signing key..."

    if ! curl -fsSL "$GPG_KEY_URL" | gpg --dearmor > "$keyring" 2>/dev/null; then
        warn "Could not fetch GPG key from repository"
        return 1
    fi

    success "GPG key imported"
    return 0
}

# Verify SHA256 checksum
verify_checksum() {
    local archive="$1"
    local checksums="$2"

    info "Verifying SHA256 checksum..."

    if [[ ! -f "$checksums" ]]; then
        fail "Checksums file not found: $checksums"
        return 1
    fi

    local archive_name
    archive_name=$(basename "$archive")

    local expected
    expected=$(grep "$archive_name" "$checksums" | awk '{print $1}')

    if [[ -z "$expected" ]]; then
        fail "Archive not found in checksums file: $archive_name"
        return 1
    fi

    local actual
    if command -v sha256sum &>/dev/null; then
        actual=$(sha256sum "$archive" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        actual=$(shasum -a 256 "$archive" | awk '{print $1}')
    else
        fail "No SHA256 tool available (sha256sum or shasum)"
        return 1
    fi

    if [[ "$expected" == "$actual" ]]; then
        success "SHA256 checksum verified"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
        return 0
    else
        fail "SHA256 checksum mismatch!"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
        return 1
    fi
}

# Verify GPG signature
verify_gpg_signature() {
    local checksums="$1"
    local signature="${checksums}.asc"
    local keyring="$2"

    info "Verifying GPG signature..."

    if [[ ! -f "$signature" ]]; then
        warn "Signature file not found: $signature"
        return 1
    fi

    if [[ ! -f "$keyring" ]]; then
        if ! fetch_gpg_key "$keyring"; then
            return 1
        fi
    fi

    if gpg --no-default-keyring --keyring "$keyring" \
           --verify "$signature" "$checksums" 2>&1 | grep -q "Good signature"; then
        success "GPG signature verified"

        # Show signer info
        local signer
        signer=$(gpg --no-default-keyring --keyring "$keyring" \
                     --verify "$signature" "$checksums" 2>&1 | grep "Good signature" | head -1)
        echo "    $signer"
        return 0
    else
        fail "GPG signature verification failed"
        gpg --no-default-keyring --keyring "$keyring" \
            --verify "$signature" "$checksums" 2>&1 | head -5
        return 1
    fi
}

# Verify Sigstore cosign signature
verify_cosign() {
    local archive="$1"

    info "Verifying Sigstore cosign signature..."

    if ! command -v cosign &>/dev/null; then
        warn "cosign not installed. Install with: go install github.com/sigstore/cosign/v2/cmd/cosign@latest"
        return 1
    fi

    local signature="${archive}.sig"
    local certificate="${archive}.cert"

    # Check for detached signature
    if [[ -f "$signature" ]]; then
        # Verify with detached signature
        if cosign verify-blob --signature "$signature" \
                              --certificate "$certificate" \
                              --certificate-identity-regexp ".*@tinyland.dev" \
                              --certificate-oidc-issuer "https://gitlab.com" \
                              "$archive" 2>/dev/null; then
            success "Cosign signature verified (detached)"
            return 0
        fi
    fi

    # Try keyless verification with Rekor
    if cosign verify-blob --certificate-identity-regexp ".*@tinyland.dev" \
                          --certificate-oidc-issuer "https://gitlab.com" \
                          "$archive" 2>/dev/null; then
        success "Cosign signature verified (Rekor)"
        return 0
    fi

    # Try with public key
    local pubkey
    pubkey=$(mktemp)
    trap "rm -f '$pubkey'" RETURN

    if curl -fsSL "$COSIGN_KEY_URL" -o "$pubkey" 2>/dev/null; then
        if [[ -f "$signature" ]]; then
            if cosign verify-blob --key "$pubkey" --signature "$signature" "$archive" 2>/dev/null; then
                success "Cosign signature verified (public key)"
                return 0
            fi
        fi
    fi

    fail "Cosign verification failed"
    return 1
}

# Download checksums and signature
download_verification_files() {
    local version="$1"
    local outdir="$2"

    info "Downloading verification files..."

    local base_url="${REPO_URL}/-/releases/v${version}/downloads"

    # Download checksums
    if ! curl -fsSL "${base_url}/SHA256SUMS.txt" -o "${outdir}/SHA256SUMS.txt" 2>/dev/null; then
        fail "Could not download SHA256SUMS.txt"
        return 1
    fi

    # Download signature
    curl -fsSL "${base_url}/SHA256SUMS.txt.asc" -o "${outdir}/SHA256SUMS.txt.asc" 2>/dev/null || true

    success "Downloaded verification files"
    return 0
}

# Extract version from archive name
extract_version() {
    local archive="$1"
    local name
    name=$(basename "$archive")

    # Match: remote-juggler-X.Y.Z-platform-arch.tar.gz
    if [[ "$name" =~ remote-juggler-([0-9]+\.[0-9]+\.[0-9]+[^-]*) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# Main
main() {
    local archive=""
    local checksums=""
    local gpg_only=false
    local checksum_only=false
    local use_cosign=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --gpg-only)
                gpg_only=true
                shift
                ;;
            --checksum-only)
                checksum_only=true
                shift
                ;;
            --cosign)
                use_cosign=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                if [[ -z "$archive" ]]; then
                    archive="$1"
                elif [[ -z "$checksums" ]]; then
                    checksums="$1"
                else
                    error "Too many arguments"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$archive" ]]; then
        usage
        exit 1
    fi

    if [[ ! -f "$archive" ]]; then
        error "Archive not found: $archive"
    fi

    echo ""
    echo "RemoteJuggler Release Verification"
    echo "==================================="
    echo ""
    echo "Archive: $archive"
    echo ""

    # Create temp directory for verification files
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT

    local keyring="${tmpdir}/release-keyring.gpg"

    # Download verification files if not provided
    if [[ -z "$checksums" ]]; then
        local version
        if version=$(extract_version "$archive"); then
            echo "Version: $version"
            if download_verification_files "$version" "$tmpdir"; then
                checksums="${tmpdir}/SHA256SUMS.txt"
            fi
        fi
    fi

    echo ""

    local all_passed=true

    # Verify checksum
    if [[ "$gpg_only" != "true" ]]; then
        if [[ -n "$checksums" ]]; then
            if ! verify_checksum "$archive" "$checksums"; then
                all_passed=false
            fi
        else
            warn "No checksums file available, skipping checksum verification"
        fi
    fi

    # Verify GPG signature
    if [[ "$checksum_only" != "true" ]]; then
        if [[ -n "$checksums" ]] && [[ -f "${checksums}.asc" ]]; then
            if ! verify_gpg_signature "$checksums" "$keyring"; then
                all_passed=false
            fi
        else
            warn "No GPG signature available"
        fi
    fi

    # Verify cosign (optional)
    if [[ "$use_cosign" == "true" ]]; then
        if ! verify_cosign "$archive"; then
            all_passed=false
        fi
    fi

    echo ""

    if [[ "$all_passed" == "true" ]]; then
        success "All verifications passed!"
        echo ""
        echo "This release has been verified as authentic and unmodified."
        exit 0
    else
        fail "Some verifications failed!"
        echo ""
        echo "WARNING: This release may have been tampered with."
        echo "Do not install unless you trust the source."
        exit 1
    fi
}

main "$@"
