# RemoteJuggler Development Commands
# Run `just --list` to see available commands
# Run `just --list --list-heading '' --list-subheadings` for grouped view

set dotenv-load
set export

# Project configuration
binary := "remote-juggler"
version := "2.0.0"
chapel_version := "2.7.0"

# Default: show help
default:
    @just --list

# =============================================================================
# Development
# =============================================================================

[group('dev')]
# Enter Nix development shell
shell:
    nix develop

[group('dev')]
[linux]
# Enter Chapel FHS environment (Linux only)
chapel-shell:
    nix develop .#chapel

[group('dev')]
[macos]
# Show Chapel info (macOS uses Homebrew)
chapel-shell:
    @echo "macOS: Using system Chapel"
    @echo "Install with: brew install chapel"
    @which chpl || echo "Chapel not found"

[group('dev')]
# Build debug version
build:
    make build

[group('dev')]
# Build release version
release:
    make release

[group('dev')]
# Build inside FHS environment (Linux)
[linux]
build-fhs:
    nix develop .#chapel --command make release

[group('dev')]
# Clean build artifacts
clean:
    make clean

[group('dev')]
# Deep clean including caches
distclean:
    make distclean
    rm -rf .mason target gtk-gui/target

# =============================================================================
# Testing
# =============================================================================

[group('test')]
# Run Chapel unit tests
test:
    make test

[group('test')]
# Run integration tests
test-integration:
    ./test/integration/test_trusted_workstation.sh

[group('test')]
# Run E2E tests (requires pytest)
test-e2e:
    pytest test/e2e/ -v

[group('test')]
# Run E2E GPG tests only
test-e2e-gpg:
    pytest test/e2e/ -v -m gpg

[group('test')]
# Run E2E TPM tests only (requires swtpm)
test-e2e-tpm:
    pytest test/e2e/ -v -m tpm

[group('test')]
# Run E2E MCP protocol tests
test-e2e-mcp:
    pytest test/e2e/test_mcp_protocol.py -v

[group('test')]
# Run E2E tests excluding hardware
test-e2e-ci:
    pytest test/e2e/ -v -m "not tpm and not secure_enclave and not yubikey and not hardware"

[group('test')]
# Run HSM workflow tests
test-e2e-hsm:
    pytest test/e2e/test_hsm_workflow.py -v

[group('test')]
# Run HSM workflow tests with swtpm (Linux)
[linux]
test-e2e-hsm-tpm:
    pytest test/e2e/test_tpm.py test/e2e/test_hsm_workflow.py -v -m "tpm or not hardware"

[group('test')]
# Run Secure Enclave tests (macOS)
[macos]
test-e2e-hsm-se:
    pytest test/e2e/test_secure_enclave.py test/e2e/test_hsm_workflow.py -v -m "secure_enclave or not hardware"

[group('test')]
# Run all tests
test-all: test test-integration test-e2e

[group('test')]
# Run linter (chplcheck)
lint:
    make lint

# =============================================================================
# HSM Library
# =============================================================================

[group('hsm')]
# Build HSM library
hsm:
    make -C pinentry all

[group('hsm')]
# Run HSM unit tests
hsm-test:
    make -C pinentry test

[group('hsm')]
# Run HSM integration tests
hsm-test-integration:
    make -C pinentry test-integration

[group('hsm')]
# Clean HSM build artifacts
hsm-clean:
    make -C pinentry clean

[group('hsm')]
# Install HSM library and pinentry
hsm-install:
    sudo make -C pinentry install

# =============================================================================
# GTK GUI (Linux only)
# =============================================================================

[linux]
[group('gui')]
# Build GTK GUI
gui-build:
    cd gtk-gui && cargo build

[linux]
[group('gui')]
# Build GTK GUI (release)
gui-release:
    cd gtk-gui && cargo build --release

[linux]
[group('gui')]
# Run GTK GUI
gui-run:
    cd gtk-gui && cargo run

[linux]
[group('gui')]
# Test GTK GUI
gui-test:
    cd gtk-gui && cargo test

[linux]
[group('gui')]
# Lint GTK GUI
gui-lint:
    cd gtk-gui && cargo fmt --check && cargo clippy -- -D warnings

[linux]
[group('gui')]
# Run GTK GUI integration tests
gui-test-integration:
    cd gtk-gui && cargo test --test integration_test

[linux]
[group('gui')]
# Run GTK GUI integration tests with display (Xvfb)
gui-test-ui:
    cd gtk-gui && xvfb-run -a cargo test --test integration_test -- --include-ignored

# =============================================================================
# Tray Apps
# =============================================================================

[macos]
[group('tray')]
# Build macOS tray app
tray-build:
    cd tray/darwin && swift build -c release

[linux]
[group('tray')]
# Build Linux tray app
tray-build:
    cd tray/linux && go build -o ../../target/release/remote-juggler-tray .

[linux]
[group('tray')]
# Test Linux tray app
tray-test:
    cd tray/linux && go test -v ./...

[macos]
[group('tray')]
# Test macOS tray app
tray-test:
    cd tray/darwin && swift test

# =============================================================================
# Nix
# =============================================================================

[group('nix')]
# Build with Nix
nix-build:
    nix build

[group('nix')]
# Build specific package
nix-build-pkg pkg:
    nix build .#{{pkg}}

[group('nix')]
# Run flake checks
nix-check:
    nix flake check

[group('nix')]
# Update flake inputs
nix-update:
    nix flake update

[group('nix')]
# Garbage collect
nix-gc:
    nix-collect-garbage -d

[group('nix')]
# Show flake info
nix-info:
    nix flake show

# =============================================================================
# Bazel (Rust, Go, Swift, C)
# =============================================================================

[group('bazel')]
# Build all Bazel targets
bazel-build:
    bazelisk build //...

[group('bazel')]
# Build GTK GUI with Bazel
bazel-gui:
    bazelisk build //gtk-gui:remote-juggler-gui

[group('bazel')]
# Build Linux tray app with Bazel
[linux]
bazel-tray:
    bazelisk build //tray/linux:remote-juggler-tray

[group('bazel')]
# Build macOS tray app with Bazel
[macos]
bazel-tray:
    bazelisk build //tray/darwin:RemoteJugglerTray

[group('bazel')]
# Build HSM library with Bazel
bazel-hsm:
    bazelisk build //pinentry:libhsm_remotejuggler

[group('bazel')]
# Run all Bazel tests
bazel-test:
    bazelisk test //...

[group('bazel')]
# Run Bazel tests with specific tag
bazel-test-tag tag:
    bazelisk test //... --test_tag_filters={{tag}}

[group('bazel')]
# Clean Bazel outputs
bazel-clean:
    bazelisk clean

[group('bazel')]
# Deep clean Bazel (expunge)
bazel-expunge:
    bazelisk clean --expunge

[group('bazel')]
# Show Bazel dependency graph
bazel-query target:
    bazelisk query "deps({{target}})" --output graph | dot -Tpng > /tmp/deps.png && xdg-open /tmp/deps.png || open /tmp/deps.png

[group('bazel')]
# Update Bazel lockfile
bazel-lock:
    bazelisk mod tidy

# =============================================================================
# Unified Build (Nix + Bazel)
# =============================================================================

[group('dev')]
# Build everything (Chapel via Nix, others via Bazel)
[linux]
build-all:
    @echo "Building Chapel CLI via Nix..."
    nix build .#remote-juggler
    @echo "Building Rust/Go/C via Bazel..."
    bazelisk build //gtk-gui:remote-juggler-gui //tray/linux:remote-juggler-tray //pinentry:libhsm_remotejuggler
    @echo "Build complete!"

[group('dev')]
# Build everything (Chapel via Make, others via Bazel)
[macos]
build-all:
    @echo "Building Chapel CLI..."
    make release
    @echo "Building Swift/C via Bazel..."
    bazelisk build //tray/darwin:RemoteJugglerTray //pinentry:libhsm_remotejuggler
    @echo "Build complete!"

# =============================================================================
# MCP/ACP
# =============================================================================

[group('mcp')]
# Run MCP server (debug build)
mcp: build
    ./target/debug/{{binary}} --mode=mcp

[group('mcp')]
# Run ACP server (debug build)
acp: build
    ./target/debug/{{binary}} --mode=acp

[group('mcp')]
# Test MCP protocol compliance
mcp-test:
    pytest test/e2e/test_mcp_protocol.py -v

# =============================================================================
# Documentation
# =============================================================================

[group('docs')]
# Build documentation
docs-build:
    mkdocs build

[group('docs')]
# Serve documentation locally
docs-serve:
    mkdocs serve

[group('docs')]
# Check documentation links
docs-check:
    mkdocs build --strict

# =============================================================================
# Release
# =============================================================================

[group('release')]
# Show current version
version:
    @echo "{{version}}"

[group('release')]
# Create release artifacts
artifacts:
    just release
    mkdir -p dist
    cp target/release/{{binary}} dist/
    @echo "Artifacts in dist/"

[group('release')]
# Tag a release
tag ver:
    git tag -s v{{ver}} -m "Release v{{ver}}"
    @echo "Tagged v{{ver}}"
    @echo "Push with: git push origin v{{ver}}"

# =============================================================================
# Setup
# =============================================================================

[group('setup')]
# First-time dev environment setup (auto-detect)
setup:
    @echo "Setting up RemoteJuggler development environment..."
    just deps
    just build
    just test
    @echo ""
    @echo "Dev setup complete! Run 'just --list' to see available commands."

[group('setup')]
# Install dependencies
deps:
    @echo "Checking dependencies..."
    @which chpl || echo "Chapel not found - install via Homebrew or Nix"
    @which cargo || echo "Rust not found - install via rustup"
    @which gpg || echo "GPG not found - install via package manager"

[group('setup')]
# Install pre-commit hooks
hooks:
    #!/usr/bin/env bash
    cat > .git/hooks/pre-commit << 'EOF'
    #!/bin/sh
    just lint
    EOF
    chmod +x .git/hooks/pre-commit
    echo "Pre-commit hook installed"

# =============================================================================
# RemoteJuggler Identity Setup
# =============================================================================

[group('rj')]
# Run first-time identity setup wizard
rj-setup:
    ./target/release/remote-juggler setup

[group('rj')]
# Run setup in auto mode (non-interactive)
rj-setup-auto:
    ./target/release/remote-juggler setup --auto

[group('rj')]
# Check current setup status
rj-setup-status:
    ./target/release/remote-juggler setup --status

[group('rj')]
# Import SSH hosts only
rj-import-ssh:
    ./target/release/remote-juggler setup --import-ssh

[group('rj')]
# Import GPG keys only
rj-import-gpg:
    ./target/release/remote-juggler setup --import-gpg

[group('rj')]
# List configured identities
rj-list:
    ./target/release/remote-juggler list

[group('rj')]
# Show current identity status
rj-status:
    ./target/release/remote-juggler status

[group('rj')]
# Switch identity
rj-switch identity:
    ./target/release/remote-juggler switch {{identity}}

[group('rj')]
# Validate identity connectivity
rj-validate identity:
    ./target/release/remote-juggler validate {{identity}}

[group('rj')]
# Check PIN storage status
rj-pin-status:
    ./target/release/remote-juggler pin status

[group('rj')]
# Store PIN for identity
rj-pin-store identity:
    ./target/release/remote-juggler pin store {{identity}}

[group('rj')]
# Clear PIN for identity
rj-pin-clear identity:
    ./target/release/remote-juggler pin clear {{identity}}

[group('rj')]
# Set security mode
rj-security-mode mode:
    ./target/release/remote-juggler security-mode {{mode}}

# =============================================================================
# Utilities
# =============================================================================

[group('util')]
# Show project info
info:
    @echo "RemoteJuggler v{{version}}"
    @echo "Chapel: {{chapel_version}}"
    @echo "OS: {{os()}} ({{os_family()}})"
    @echo "Arch: {{arch()}}"
    @echo "CPUs: {{num_cpus()}}"

[group('util')]
# Format Nix files
fmt-nix:
    nixfmt flake.nix nix/

[group('util')]
# Check all formatting
fmt-check:
    just lint
    just gui-lint || true
    nixfmt --check flake.nix nix/ || true

[group('util')]
# Watch for changes and rebuild
watch:
    @echo "Watching for changes..."
    @echo "Press Ctrl+C to stop"
    while true; do \
        inotifywait -r -e modify src/; \
        just build; \
    done

# =============================================================================
# Distribution
# =============================================================================

[group('dist')]
# Generate release checksums
dist-checksums:
    #!/usr/bin/env bash
    cd dist/
    sha256sum *.tar.gz *.zip 2>/dev/null > SHA256SUMS.txt || true
    echo "Generated SHA256SUMS.txt"
    cat SHA256SUMS.txt

[group('dist')]
# Sign release checksums with GPG
dist-sign:
    #!/usr/bin/env bash
    cd dist/
    gpg --armor --detach-sign SHA256SUMS.txt
    echo "Signed SHA256SUMS.txt -> SHA256SUMS.txt.asc"

[group('dist')]
# Verify release archive
dist-verify archive:
    ./scripts/verify-release.sh {{archive}}

[group('dist')]
# Generate changelog for release
dist-changelog from="" to="HEAD":
    ./scripts/generate-changelog.sh --from {{from}} --to {{to}} --emoji --contributors --stats

[group('dist')]
# Generate changelog in GitHub format
dist-changelog-github from="" to="HEAD":
    ./scripts/generate-changelog.sh --from {{from}} --to {{to}} --format github --emoji

[group('dist')]
# Build release tarball
dist-tarball:
    #!/usr/bin/env bash
    set -e
    VERSION={{version}}
    PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')"
    TARBALL="dist/remote-juggler-${VERSION}-${PLATFORM}.tar.gz"
    mkdir -p dist/
    tar -czf "$TARBALL" -C target/release remote-juggler
    echo "Created: $TARBALL"
    sha256sum "$TARBALL" || shasum -a 256 "$TARBALL"

[group('dist')]
# Build all distribution artifacts
dist-all: release dist-tarball dist-checksums

[group('dist')]
# Build AUR package locally
[linux]
dist-aur:
    cd packaging/aur && makepkg -si

[group('dist')]
# Build Flatpak locally
[linux]
dist-flatpak:
    flatpak-builder --user --install build-flatpak packaging/flatpak/dev.tinyland.RemoteJuggler.yml

[group('dist')]
# Test install script (dry run)
dist-test-install:
    ./scripts/install.sh --help

# =============================================================================
# CI Helpers
# =============================================================================

[group('ci')]
# Run CI checks locally
ci: lint test-all

[group('ci')]
# Run ALL tests (unified entry point for CI)
test-all-ci: lint
    @echo "=== Running Chapel unit tests ==="
    make test || true
    @echo ""
    @echo "=== Running Bazel tests (Rust/Go/C/Swift) ==="
    bazelisk test //gtk-gui:... //tray/...:... //pinentry:... --test_tag_filters=-hardware || true
    @echo ""
    @echo "=== Running E2E tests (pytest) ==="
    pytest test/e2e/ -m "not tpm and not secure_enclave and not yubikey and not hardware" -v || true
    @echo ""
    @echo "=== CI test run complete ==="

[group('ci')]
# Run full Bazel test suite with E2E
bazel-test-full:
    bazelisk test //... --test_tag_filters=-hardware

[group('ci')]
# Run all tests including hardware tests (requires TPM/SE)
test-all-hardware: lint
    @echo "=== Running all tests including hardware ==="
    make test || true
    bazelisk test //... || true
    pytest test/e2e/ -v || true

[group('ci')]
# Simulate GitLab CI
ci-simulate:
    @echo "Running CI simulation..."
    just lint
    just test
    just test-integration
    just hsm-test
    just gui-test || true
    @echo "CI simulation complete"

# =============================================================================
# Man Page
# =============================================================================

[group('docs')]
# Install man page
docs-man-install:
    #!/usr/bin/env bash
    set -e
    MAN_DIR="${MAN_DIR:-/usr/local/share/man/man1}"
    sudo mkdir -p "$MAN_DIR"
    sudo install -m 644 docs/man/remote-juggler.1 "$MAN_DIR/"
    sudo mandb 2>/dev/null || true
    echo "Man page installed to $MAN_DIR/remote-juggler.1"
    echo "View with: man remote-juggler"

[group('docs')]
# Preview man page without installing
docs-man-preview:
    man docs/man/remote-juggler.1

[group('docs')]
# Generate man page from markdown (if using pandoc)
docs-man-generate:
    @echo "Man page is maintained directly in docs/man/remote-juggler.1"
    @echo "Edit that file directly using troff/groff format."
