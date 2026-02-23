# RemoteJuggler Development Commands
# Run `just --list` to see available commands
# Run `just --list --list-heading '' --list-subheadings` for grouped view

set dotenv-load
set export

# Project configuration
binary := "remote-juggler"
version := "2.1.0"
chapel_version := "2.7.0"

# Installation paths
home := env_var("HOME")
prefix := env_var_or_default("PREFIX", home / ".local")
bindir := prefix / "bin"
mandir := prefix / "share/man/man1"
compdir_bash := home / ".local/share/bash-completion/completions"
compdir_zsh := home / ".zsh/completions"
compdir_fish := home / ".config/fish/completions"
config_dir := home / ".config/remote-juggler"
claude_dir := home / ".claude"

# Chapel compiler flags
chpl_flags := "-M src/remote_juggler"

# HSM paths
hsm_dir := "pinentry"
hsm_lib_linux := hsm_dir / "libhsm_remotejuggler.so"
hsm_lib_darwin := hsm_dir / "libhsm_remotejuggler.dylib"

# Default: show help
default:
    @just --list

# Build and test everything (equivalent of old `make all`)
[group('dev')]
all: lint build test

# =============================================================================
# Development
# =============================================================================

# Enter Nix development shell
[group('dev')]
shell:
    nix develop

# Enter Chapel FHS environment (Linux only)
[group('dev')]
[linux]
chapel-shell:
    nix develop .#chapel

# Show Chapel info (macOS uses Homebrew)
[group('dev')]
[macos]
chapel-shell:
    @echo "macOS: Using system Chapel"
    @echo "Install with: brew install chapel"
    @which chpl || echo "Chapel not found"

# Build debug version (Linux)
[group('dev')]
[linux]
build: hsm
    #!/usr/bin/env bash
    set -e
    echo "Building RemoteJuggler (debug)..."
    mkdir -p target/debug
    if [ -f "{{hsm_lib_linux}}" ]; then
        echo "  [HSM] Native HSM library found, linking..."
        HSM_CFLAGS="--ccflags=-I$(pwd)/{{hsm_dir}}"
        TPM_LIBS=""
        if pkg-config --exists tss2-esys 2>/dev/null; then
            TPM_LIBS="$(pkg-config --libs tss2-esys tss2-rc tss2-tctildr)"
        fi
        HSM_LDFLAGS="--ldflags=-L$(pwd)/{{hsm_dir}} -lhsm_remotejuggler -Wl,-rpath,$(pwd)/{{hsm_dir}} $TPM_LIBS"
        HSM_FLAG="-sHSM_NATIVE_AVAILABLE=true"
        chpl {{chpl_flags}} "$HSM_CFLAGS" "$HSM_LDFLAGS" "$HSM_FLAG" -o target/debug/{{binary}} src/remote_juggler.chpl
    else
        echo "  [HSM] Native HSM library not found, using stub implementation..."
        chpl {{chpl_flags}} -sHSM_NATIVE_AVAILABLE=false -o target/debug/{{binary}} src/remote_juggler.chpl
    fi

# Build debug version (macOS)
[group('dev')]
[macos]
build: hsm
    #!/usr/bin/env bash
    set -e
    echo "Building RemoteJuggler (debug)..."
    mkdir -p target/debug
    LDFLAGS="--ldflags=-framework Security -framework CoreFoundation"
    if [ -f "{{hsm_lib_darwin}}" ]; then
        echo "  [HSM] Native HSM library found, linking..."
        HSM_CFLAGS="--ccflags=-I$(pwd)/{{hsm_dir}}"
        HSM_LDFLAGS="--ldflags=-L$(pwd)/{{hsm_dir}} -lhsm_remotejuggler -framework Security -framework CoreFoundation"
        chpl {{chpl_flags}} "$HSM_CFLAGS" "$HSM_LDFLAGS" -sHSM_NATIVE_AVAILABLE=true -o target/debug/{{binary}} src/remote_juggler.chpl
    else
        echo "  [HSM] Native HSM library not found, using stub implementation..."
        chpl {{chpl_flags}} "$LDFLAGS" -sHSM_NATIVE_AVAILABLE=false -o target/debug/{{binary}} src/remote_juggler.chpl
    fi

# Build release version (Linux)
[group('dev')]
[linux]
release: hsm
    #!/usr/bin/env bash
    set -e
    echo "Building RemoteJuggler (release)..."
    mkdir -p target/release
    if [ -f "{{hsm_lib_linux}}" ]; then
        echo "  [HSM] Native HSM library found, linking..."
        HSM_CFLAGS="--ccflags=-I$(pwd)/{{hsm_dir}}"
        TPM_LIBS=""
        if pkg-config --exists tss2-esys 2>/dev/null; then
            TPM_LIBS="$(pkg-config --libs tss2-esys tss2-rc tss2-tctildr)"
        fi
        HSM_LDFLAGS="--ldflags=-L$(pwd)/{{hsm_dir}} -lhsm_remotejuggler -Wl,-rpath,$(pwd)/{{hsm_dir}} $TPM_LIBS"
        HSM_FLAG="-sHSM_NATIVE_AVAILABLE=true"
        chpl {{chpl_flags}} "$HSM_CFLAGS" "$HSM_LDFLAGS" "$HSM_FLAG" --fast -o target/release/remote_juggler src/remote_juggler.chpl
    else
        echo "  [HSM] Native HSM library not found, using stub implementation..."
        chpl {{chpl_flags}} -sHSM_NATIVE_AVAILABLE=false --fast -o target/release/remote_juggler src/remote_juggler.chpl
    fi

# Build release version (macOS)
[group('dev')]
[macos]
release: hsm
    #!/usr/bin/env bash
    set -e
    echo "Building RemoteJuggler (release)..."
    mkdir -p target/release
    LDFLAGS="--ldflags=-framework Security -framework CoreFoundation"
    if [ -f "{{hsm_lib_darwin}}" ]; then
        echo "  [HSM] Native HSM library found, linking..."
        HSM_CFLAGS="--ccflags=-I$(pwd)/{{hsm_dir}}"
        HSM_LDFLAGS="--ldflags=-L$(pwd)/{{hsm_dir}} -lhsm_remotejuggler -framework Security -framework CoreFoundation"
        chpl {{chpl_flags}} "$HSM_CFLAGS" "$HSM_LDFLAGS" -sHSM_NATIVE_AVAILABLE=true --fast -o target/release/remote_juggler src/remote_juggler.chpl
    else
        echo "  [HSM] Native HSM library not found, using stub implementation..."
        chpl {{chpl_flags}} "$LDFLAGS" -sHSM_NATIVE_AVAILABLE=false --fast -o target/release/remote_juggler src/remote_juggler.chpl
    fi

# Build inside FHS environment (Linux)
[group('dev')]
[linux]
build-fhs:
    nix develop .#chapel --command just release

# Clean build artifacts
[group('dev')]
clean: hsm-clean
    @echo "Cleaning build artifacts..."
    rm -rf target/
    rm -f test-results.xml
    rm -f chplcheck-report.txt

# Deep clean including caches
[group('dev')]
distclean: clean
    rm -rf .mason/
    rm -f Mason.lock
    rm -rf gtk-gui/target

# =============================================================================
# Testing
# =============================================================================

# Run Chapel unit tests
[group('test')]
test:
    @echo "Running tests..."
    ./scripts/run-tests.sh

# Run chplcheck linter
[group('test')]
lint:
    @echo "Running chplcheck linter..."
    ./scripts/run-chplcheck.sh

# Run lint and tests
[group('test')]
check: lint test

# Chapel compilation smoke test (no codegen, catches type errors fast)
[group('test')]
check-compile:
    @echo "Checking Chapel compilation (no codegen)..."
    chpl --no-codegen -sHSM_NATIVE_AVAILABLE=false {{chpl_flags}} src/remote_juggler.chpl
    @echo "Chapel compilation check passed."

# Run integration tests
[group('test')]
test-integration: build
    ./test/integration/test_trusted_workstation.sh --binary target/debug/{{binary}}

# Run integration tests with TAP output
[group('test')]
test-integration-tap: build
    ./test/integration/test_trusted_workstation.sh --binary target/debug/{{binary}} --tap

# Run E2E tests (requires pytest)
[group('test')]
test-e2e:
    pytest test/e2e/ -v

# Run E2E GPG tests only
[group('test')]
test-e2e-gpg:
    pytest test/e2e/ -v -m gpg

# Run E2E TPM tests only
[group('test')]
test-e2e-tpm:
    pytest test/e2e/ -v -m tpm

# Run E2E MCP protocol tests
[group('test')]
test-e2e-mcp:
    pytest test/e2e/test_mcp_protocol.py -v

# Run E2E tests excluding hardware
[group('test')]
test-e2e-ci:
    pytest test/e2e/ -v -m "not tpm and not secure_enclave and not yubikey and not hardware"

# Run HSM workflow tests
[group('test')]
test-e2e-hsm:
    pytest test/e2e/test_hsm_workflow.py -v

# Run HSM workflow tests with swtpm (Linux)
[group('test')]
[linux]
test-e2e-hsm-tpm:
    pytest test/e2e/test_tpm.py test/e2e/test_hsm_workflow.py -v -m "tpm or not hardware"

# Run Secure Enclave tests (macOS)
[group('test')]
[macos]
test-e2e-hsm-se:
    pytest test/e2e/test_secure_enclave.py test/e2e/test_hsm_workflow.py -v -m "secure_enclave or not hardware"

# Run all tests
[group('test')]
test-all: test test-integration test-e2e

# =============================================================================
# HSM Library
# =============================================================================

# Build HSM library
[group('hsm')]
hsm:
    @echo "Building HSM library..."
    @make -C {{hsm_dir}} all || { \
        echo ""; \
        echo "WARNING: HSM library build failed or TPM2-TSS not available."; \
        echo "         Building without native HSM support (stub mode)."; \
        echo ""; \
    }

# Run HSM unit tests
[group('hsm')]
hsm-test:
    make -C {{hsm_dir}} test

# Run HSM integration tests
[group('hsm')]
hsm-test-integration:
    make -C {{hsm_dir}} test-integration

# Clean HSM build artifacts
[group('hsm')]
hsm-clean:
    @make -C {{hsm_dir}} clean 2>/dev/null || true

# Install HSM library and pinentry (requires sudo)
[group('hsm')]
hsm-install:
    sudo make -C {{hsm_dir}} install

# =============================================================================
# Installation
# =============================================================================

# Full user-wide installation
[group('install')]
install: release install-binary install-config install-completions install-claude
    @echo ""
    @echo "{{binary}} installed successfully!"
    @echo ""
    @echo "Run '{{binary}} --help' to get started"
    @echo "Run 'just info' to see installation paths"

# Install from source (development build)
[group('install')]
install-dev: build
    @echo "Installing development build..."
    mkdir -p {{bindir}}
    cp target/debug/{{binary}} {{bindir}}/{{binary}}
    chmod +x {{bindir}}/{{binary}}
    @echo "Installed to {{bindir}}/{{binary}}"

# Install binary only
[group('install')]
install-binary: release
    @echo "Installing binary to {{bindir}}..."
    mkdir -p {{bindir}}
    cp target/release/remote_juggler {{bindir}}/{{binary}}
    chmod +x {{bindir}}/{{binary}}
    @echo "Binary installed: {{bindir}}/{{binary}}"

# Initialize configuration
[group('install')]
install-config:
    #!/usr/bin/env bash
    echo "Initializing configuration..."
    mkdir -p {{config_dir}}
    if [ ! -f "{{config_dir}}/config.json" ]; then
        echo '{"version":"2.0.0","identities":{},"settings":{"defaultProvider":"gitlab","autoDetect":true,"useKeychain":true,"gpgSign":true}}' > {{config_dir}}/config.json
        echo "Created {{config_dir}}/config.json"
    else
        echo "Config already exists at {{config_dir}}/config.json"
    fi

# Install shell completions
[group('install')]
install-completions: release
    #!/usr/bin/env bash
    echo "Installing shell completions..."
    mkdir -p {{compdir_bash}} {{compdir_zsh}} {{compdir_fish}}
    {{bindir}}/{{binary}} --completions=bash > {{compdir_bash}}/{{binary}} 2>/dev/null || \
        ./scripts/generate-completions.sh bash > {{compdir_bash}}/{{binary}}
    {{bindir}}/{{binary}} --completions=zsh > {{compdir_zsh}}/_{{binary}} 2>/dev/null || \
        ./scripts/generate-completions.sh zsh > {{compdir_zsh}}/_{{binary}}
    {{bindir}}/{{binary}} --completions=fish > {{compdir_fish}}/{{binary}}.fish 2>/dev/null || \
        ./scripts/generate-completions.sh fish > {{compdir_fish}}/{{binary}}.fish
    echo "Completions installed for bash, zsh, and fish"

# Install Claude Code integration
[group('install')]
install-claude:
    #!/usr/bin/env bash
    echo "Installing Claude Code integration..."
    mkdir -p {{claude_dir}}/commands {{claude_dir}}/skills/git-identity
    if [ -d .claude/commands ]; then
        cp .claude/commands/*.md {{claude_dir}}/commands/ 2>/dev/null || true
    fi
    if [ -d .claude/skills/git-identity ]; then
        cp .claude/skills/git-identity/*.md {{claude_dir}}/skills/git-identity/ 2>/dev/null || true
    fi
    echo "Claude Code slash commands and skills installed"

# Install MCP config to current directory
[group('install')]
install-mcp:
    #!/usr/bin/env bash
    echo "Installing .mcp.json to current directory..."
    if [ -f .mcp.json ]; then
        echo "Warning: .mcp.json already exists"
    else
        echo '{"mcpServers":{"remote-juggler":{"command":"{{binary}}","args":["--mode=mcp"]}}}' > .mcp.json
        echo "Created .mcp.json"
    fi

# Install GTK GUI binary (Linux)
[group('install')]
[linux]
install-gui: gui-release
    @echo "Installing GTK GUI to {{bindir}}..."
    cp gtk-gui/target/release/remote-juggler-gui {{bindir}}/
    chmod +x {{bindir}}/remote-juggler-gui
    @echo "GUI installed: {{bindir}}/remote-juggler-gui"

# Install tray app binary (Linux)
[group('install')]
[linux]
install-tray: tray-build
    @echo "Installing tray app to {{bindir}}..."
    cp target/release/remote-juggler-tray {{bindir}}/
    chmod +x {{bindir}}/remote-juggler-tray
    @echo "Tray installed: {{bindir}}/remote-juggler-tray"

# Install desktop entry for GUI (Linux)
[group('install')]
[linux]
install-desktop:
    #!/usr/bin/env bash
    echo "Installing desktop entry..."
    APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    mkdir -p "$APPS_DIR"
    cp gtk-gui/data/dev.tinyland.RemoteJuggler.desktop "$APPS_DIR/"
    echo "Desktop entry installed: $APPS_DIR/dev.tinyland.RemoteJuggler.desktop"
    # Update desktop database if available
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$APPS_DIR" 2>/dev/null || true
    fi

# Install autostart entry for tray (Linux)
[group('install')]
[linux]
install-autostart:
    #!/usr/bin/env bash
    echo "Installing autostart entry..."
    AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
    mkdir -p "$AUTOSTART_DIR"
    cp packaging/autostart.desktop "$AUTOSTART_DIR/remote-juggler.desktop"
    echo "Autostart entry installed: $AUTOSTART_DIR/remote-juggler.desktop"
    echo "Tray will start automatically on next login"

# Install all components (CLI, GUI, tray, desktop entries)
[group('install')]
[linux]
install-all: install install-gui install-tray install-desktop install-autostart

# Uninstall RemoteJuggler
[group('install')]
uninstall:
    #!/usr/bin/env bash
    echo "Uninstalling RemoteJuggler..."
    rm -f {{bindir}}/{{binary}}
    rm -f {{bindir}}/remote-juggler-gui
    rm -f {{bindir}}/remote-juggler-tray
    rm -f {{compdir_bash}}/{{binary}}
    rm -f {{compdir_zsh}}/_{{binary}}
    rm -f {{compdir_fish}}/{{binary}}.fish
    # Remove desktop entries
    APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
    rm -f "$APPS_DIR/dev.tinyland.RemoteJuggler.desktop"
    rm -f "$AUTOSTART_DIR/remote-juggler.desktop"
    echo "Binary, completions, and desktop entries removed"
    echo ""
    echo "Config preserved at {{config_dir}}"
    echo "Claude integration preserved at {{claude_dir}}"
    echo "Remove manually if desired"

# =============================================================================
# GTK GUI (Linux only)
# =============================================================================

# Build GTK GUI
[linux]
[group('gui')]
gui-build:
    cd gtk-gui && cargo build

# Build GTK GUI (release, prefer Nix-wrapped for proper GApps environment)
[linux]
[group('gui')]
gui-release:
    #!/usr/bin/env bash
    set -e
    if command -v nix &>/dev/null && nix build .#remote-juggler-gui 2>/dev/null; then
        echo "Built GTK GUI via Nix (GApps-wrapped)"
        mkdir -p gtk-gui/target/release
        cp -f result/bin/remote-juggler-gui gtk-gui/target/release/
    else
        echo "Nix build unavailable, falling back to cargo build"
        cd gtk-gui && cargo build --release
    fi

# Run GTK GUI
[linux]
[group('gui')]
gui-run:
    cd gtk-gui && cargo run

# Test GTK GUI
[linux]
[group('gui')]
gui-test:
    cd gtk-gui && cargo test

# Lint GTK GUI
[linux]
[group('gui')]
gui-lint:
    cd gtk-gui && cargo fmt --check && cargo clippy -- -D warnings

# Run GTK GUI integration tests
[linux]
[group('gui')]
gui-test-integration:
    cd gtk-gui && cargo test --test integration_test

# Run GTK GUI integration tests with display (Xvfb)
[linux]
[group('gui')]
gui-test-ui:
    cd gtk-gui && xvfb-run -a cargo test --test integration_test -- --include-ignored

# =============================================================================
# Tray Apps
# =============================================================================

# Build macOS tray app
[macos]
[group('tray')]
tray-build:
    cd tray/darwin && swift build -c release

# Build Linux tray app
[linux]
[group('tray')]
tray-build:
    cd tray/linux && go build -o ../../target/release/remote-juggler-tray .

# Test Linux tray app
[linux]
[group('tray')]
tray-test:
    cd tray/linux && go test -v ./...

# Test macOS tray app
[macos]
[group('tray')]
tray-test:
    cd tray/darwin && swift test

# =============================================================================
# Gateway
# =============================================================================

# Build gateway binary
[group('gateway')]
gateway-build:
    cd gateway && go build -o ../target/release/rj-gateway .

# Run gateway in local mode (no tsnet)
[group('gateway')]
gateway-run: gateway-build
    ./target/release/rj-gateway --listen=localhost:8443 --chapel-bin=./target/release/remote_juggler

# Run gateway tests
[group('gateway')]
gateway-test:
    cd gateway && go test -v ./...

# Lint gateway
[group('gateway')]
gateway-lint:
    cd gateway && go vet ./...

# Build gateway Docker image
[group('gateway')]
gateway-docker:
    cd gateway && docker build -t ghcr.io/tinyland-inc/remote-juggler/gateway:latest .

# Build gateway with Nix
[group('gateway')]
gateway-nix:
    nix build .#rj-gateway

# =============================================================================
# Nix
# =============================================================================

# Build with Nix
[group('nix')]
nix-build:
    nix build

# Build specific package
[group('nix')]
nix-build-pkg pkg:
    nix build .#{{pkg}}

# Run flake checks
[group('nix')]
nix-check:
    nix flake check

# Update flake inputs
[group('nix')]
nix-update:
    nix flake update

# Garbage collect
[group('nix')]
nix-gc:
    nix-collect-garbage -d

# Show flake info
[group('nix')]
nix-info:
    nix flake show

# =============================================================================
# Bazel (Rust, Go, Swift, C)
# =============================================================================

# Build all Bazel targets
[group('bazel')]
bazel-build:
    bazelisk build //...

# Build GTK GUI with Bazel
[group('bazel')]
bazel-gui:
    bazelisk build //gtk-gui:remote-juggler-gui

# Build Linux tray app with Bazel
[group('bazel')]
[linux]
bazel-tray:
    bazelisk build //tray/linux:remote-juggler-tray

# Build macOS tray app with Bazel
[group('bazel')]
[macos]
bazel-tray:
    bazelisk build //tray/darwin:RemoteJugglerTray

# Build gateway with Bazel
[group('bazel')]
bazel-gateway:
    bazelisk build //gateway:rj-gateway

# Build HSM library with Bazel
[group('bazel')]
bazel-hsm:
    bazelisk build //pinentry:libhsm_remotejuggler

# Run all Bazel tests
[group('bazel')]
bazel-test:
    bazelisk test //...

# Run Bazel tests with specific tag
[group('bazel')]
bazel-test-tag tag:
    bazelisk test //... --test_tag_filters={{tag}}

# Clean Bazel outputs
[group('bazel')]
bazel-clean:
    bazelisk clean

# Deep clean Bazel (expunge)
[group('bazel')]
bazel-expunge:
    bazelisk clean --expunge

# Show Bazel dependency graph
[group('bazel')]
bazel-query target:
    bazelisk query "deps({{target}})" --output graph | dot -Tpng > /tmp/deps.png && xdg-open /tmp/deps.png || open /tmp/deps.png

# Update Bazel lockfile
[group('bazel')]
bazel-lock:
    bazelisk mod tidy

# =============================================================================
# Unified Build (Nix + Bazel)
# =============================================================================

# Build everything (Linux: Chapel via Nix, others via Bazel)
[group('dev')]
[linux]
build-all:
    @echo "Building Chapel CLI via Nix..."
    nix build .#remote-juggler
    @echo "Building Rust/Go/C via Bazel..."
    bazelisk build //gtk-gui:remote-juggler-gui //tray/linux:remote-juggler-tray //pinentry:libhsm_remotejuggler
    @echo "Build complete!"

# Build everything (macOS: Chapel via just, others via Bazel)
[group('dev')]
[macos]
build-all:
    @echo "Building Chapel CLI..."
    just release
    @echo "Building Swift/C via Bazel..."
    bazelisk build //tray/darwin:RemoteJugglerTray //pinentry:libhsm_remotejuggler
    @echo "Build complete!"

# =============================================================================
# MCP/ACP
# =============================================================================

# Run MCP server (debug build)
[group('mcp')]
mcp: build
    ./target/debug/{{binary}} --mode=mcp

# Run ACP server (debug build)
[group('mcp')]
acp: build
    ./target/debug/{{binary}} --mode=acp

# Test MCP protocol compliance
[group('mcp')]
mcp-test:
    pytest test/e2e/test_mcp_protocol.py -v

# =============================================================================
# Documentation
# =============================================================================

# Build documentation
[group('docs')]
docs-build:
    mkdocs build

# Serve documentation locally
[group('docs')]
docs-serve:
    mkdocs serve

# Check documentation links
[group('docs')]
docs-check:
    mkdocs build --strict

# Install man page
[group('docs')]
docs-man-install:
    #!/usr/bin/env bash
    set -e
    MAN_DIR="${MAN_DIR:-/usr/local/share/man/man1}"
    sudo mkdir -p "$MAN_DIR"
    sudo install -m 644 docs/man/remote-juggler.1 "$MAN_DIR/"
    sudo mandb 2>/dev/null || true
    echo "Man page installed to $MAN_DIR/remote-juggler.1"

# Preview man page without installing
[group('docs')]
docs-man-preview:
    man docs/man/remote-juggler.1

# =============================================================================
# Release
# =============================================================================

# Show current version
[group('release')]
version:
    @echo "{{version}}"

# Create release artifacts
[group('release')]
artifacts:
    just release
    mkdir -p dist
    cp target/release/remote_juggler dist/{{binary}}
    @echo "Artifacts in dist/"

# Tag a release
[group('release')]
tag ver:
    git tag -s v{{ver}} -m "Release v{{ver}}"
    @echo "Tagged v{{ver}}"
    @echo "Push with: git push origin v{{ver}}"

# =============================================================================
# Setup
# =============================================================================

# First-time dev environment setup
[group('setup')]
setup:
    @echo "Setting up RemoteJuggler development environment..."
    just deps
    just build
    just test
    @echo ""
    @echo "Dev setup complete! Run 'just --list' to see available commands."

# Check/install dependencies
[group('setup')]
deps:
    #!/usr/bin/env bash
    echo "Checking dependencies..."
    echo ""
    echo "Chapel:  $(which chpl 2>/dev/null && chpl --version | head -1 || echo 'Not found - install via Homebrew or Nix')"
    echo "Cargo:   $(which cargo 2>/dev/null && cargo --version || echo 'Not found - install via rustup')"
    echo "Go:      $(which go 2>/dev/null && go version || echo 'Not found - install via package manager')"
    echo "GPG:     $(which gpg 2>/dev/null && gpg --version | head -1 || echo 'Not found - install via package manager')"
    echo ""
    echo "Fetching Mason dependencies..."
    mkdir -p $HOME/.mason/registry
    if ! grep -q "tinyland" $HOME/.mason/registry/mason-registry.toml 2>/dev/null; then
        echo '[[registry]]' >> $HOME/.mason/registry/mason-registry.toml
        echo 'name = "tinyland"' >> $HOME/.mason/registry/mason-registry.toml
        echo 'source = "https://github.com/Jesssullivan/mason-registry"' >> $HOME/.mason/registry/mason-registry.toml
        echo 'branch = "sid"' >> $HOME/.mason/registry/mason-registry.toml
        echo "Added tinyland registry"
    fi
    mason update 2>/dev/null || echo "Mason update skipped (mason not installed)"

# Install pre-commit hooks
[group('setup')]
hooks:
    #!/usr/bin/env bash
    cat > .git/hooks/pre-commit << 'EOF'
    #!/bin/sh
    just lint
    EOF
    chmod +x .git/hooks/pre-commit
    echo "Pre-commit hook installed"

# =============================================================================
# RemoteJuggler Identity Commands
# =============================================================================

# Run first-time identity setup wizard
[group('rj')]
rj-setup:
    ./target/release/remote_juggler setup

# Run setup in auto mode (non-interactive)
[group('rj')]
rj-setup-auto:
    ./target/release/remote_juggler setup --auto

# Check current setup status
[group('rj')]
rj-setup-status:
    ./target/release/remote_juggler setup --status

# Import SSH hosts only
[group('rj')]
rj-import-ssh:
    ./target/release/remote_juggler setup --import-ssh

# Import GPG keys only
[group('rj')]
rj-import-gpg:
    ./target/release/remote_juggler setup --import-gpg

# List configured identities
[group('rj')]
rj-list:
    ./target/release/remote_juggler list

# Show current identity status
[group('rj')]
rj-status:
    ./target/release/remote_juggler status

# Switch identity
[group('rj')]
rj-switch identity:
    ./target/release/remote_juggler switch {{identity}}

# Validate identity connectivity
[group('rj')]
rj-validate identity:
    ./target/release/remote_juggler validate {{identity}}

# Check PIN storage status
[group('rj')]
rj-pin-status:
    ./target/release/remote_juggler pin status

# Store PIN for identity
[group('rj')]
rj-pin-store identity:
    ./target/release/remote_juggler pin store {{identity}}

# Clear PIN for identity
[group('rj')]
rj-pin-clear identity:
    ./target/release/remote_juggler pin clear {{identity}}

# Set security mode
[group('rj')]
rj-security-mode mode:
    ./target/release/remote_juggler security-mode {{mode}}

# =============================================================================
# Utilities
# =============================================================================

# Show project info
[group('util')]
info:
    #!/usr/bin/env bash
    echo "RemoteJuggler v{{version}}"
    echo "Chapel: {{chapel_version}}"
    echo "OS: {{os()}} ({{os_family()}})"
    echo "Arch: {{arch()}}"
    echo "CPUs: {{num_cpus()}}"
    echo ""
    echo "Installation Paths:"
    echo "  Binary:       {{bindir}}/{{binary}}"
    echo "  Config:       {{config_dir}}/config.json"
    echo ""
    echo "Completions:"
    echo "  Bash:         {{compdir_bash}}/{{binary}}"
    echo "  Zsh:          {{compdir_zsh}}/_{{binary}}"
    echo "  Fish:         {{compdir_fish}}/{{binary}}.fish"
    echo ""
    echo "Claude Code:"
    echo "  Commands:     {{claude_dir}}/commands/"
    echo "  Skills:       {{claude_dir}}/skills/git-identity/"
    echo ""
    echo "HSM Support:"
    echo "  Platform:     {{os()}}"
    if [ "{{os()}}" = "linux" ]; then
        if pkg-config --exists tss2-esys 2>/dev/null; then
            echo "  Backend:      TPM 2.0 (tss2-esys available)"
        else
            echo "  Backend:      Stub (tss2-esys not found)"
        fi
        echo "  Library:      {{hsm_lib_linux}}"
        test -f "{{hsm_lib_linux}}" && echo "  Status:       Built" || echo "  Status:       Not built"
    else
        echo "  Backend:      Secure Enclave / Keychain"
        echo "  Library:      {{hsm_lib_darwin}}"
        test -f "{{hsm_lib_darwin}}" && echo "  Status:       Built" || echo "  Status:       Not built"
    fi
    echo ""
    if [ -x "{{bindir}}/{{binary}}" ]; then
        echo "Status: Installed"
        {{bindir}}/{{binary}} --version 2>/dev/null || echo "  (version check failed)"
    else
        echo "Status: Not installed"
    fi

# Format Nix files
[group('util')]
fmt-nix:
    nixfmt flake.nix nix/

# Check all formatting
[group('util')]
fmt-check:
    just lint
    just gui-lint || true
    nixfmt --check flake.nix nix/ || true

# Watch for changes and rebuild
[group('util')]
watch:
    @echo "Watching for changes..."
    @echo "Press Ctrl+C to stop"
    while true; do \
        inotifywait -r -e modify src/; \
        just build; \
    done

# Show help
[group('util')]
help:
    #!/usr/bin/env bash
    echo "RemoteJuggler Development Commands"
    echo "==================================="
    echo ""
    echo "Building:"
    echo "  just build        Build debug version (includes HSM)"
    echo "  just release      Build release version (optimized)"
    echo "  just hsm          Build HSM library only"
    echo ""
    echo "Testing:"
    echo "  just test                   Run unit tests"
    echo "  just lint                   Run chplcheck linter"
    echo "  just check                  Run lint + test"
    echo "  just test-integration       Run integration tests"
    echo "  just test-all               Run unit + integration + E2E tests"
    echo ""
    echo "Installation:"
    echo "  just install                Full user-wide installation"
    echo "  just install-dev            Install debug build for development"
    echo "  just install-all            Install CLI + GUI + tray (Linux)"
    echo "  just uninstall              Remove installed files"
    echo ""
    echo "Utilities:"
    echo "  just deps                   Check/fetch dependencies"
    echo "  just clean                  Remove build artifacts"
    echo "  just distclean              Clean + remove caches"
    echo "  just mcp                    Run MCP server mode"
    echo "  just acp                    Run ACP server mode"
    echo "  just info                   Show installation paths"
    echo ""
    echo "Run 'just --list' for full command list"

# =============================================================================
# Distribution
# =============================================================================

# Generate release checksums
[group('dist')]
dist-checksums:
    #!/usr/bin/env bash
    cd dist/
    sha256sum *.tar.gz *.zip 2>/dev/null > SHA256SUMS.txt || true
    echo "Generated SHA256SUMS.txt"
    cat SHA256SUMS.txt

# Sign release checksums with GPG
[group('dist')]
dist-sign:
    #!/usr/bin/env bash
    cd dist/
    gpg --armor --detach-sign SHA256SUMS.txt
    echo "Signed SHA256SUMS.txt -> SHA256SUMS.txt.asc"

# Verify release archive
[group('dist')]
dist-verify archive:
    ./scripts/verify-release.sh {{archive}}

# Generate changelog for release
[group('dist')]
dist-changelog from="" to="HEAD":
    ./scripts/generate-changelog.sh --from {{from}} --to {{to}} --emoji --contributors --stats

# Generate changelog in GitHub format
[group('dist')]
dist-changelog-github from="" to="HEAD":
    ./scripts/generate-changelog.sh --from {{from}} --to {{to}} --format github --emoji

# Build release tarball
[group('dist')]
dist-tarball:
    #!/usr/bin/env bash
    set -e
    VERSION={{version}}
    PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')"
    TARBALL="dist/remote-juggler-${VERSION}-${PLATFORM}.tar.gz"
    mkdir -p dist/
    tar -czf "$TARBALL" -C target/release remote_juggler
    echo "Created: $TARBALL"
    sha256sum "$TARBALL" || shasum -a 256 "$TARBALL"

# Build all distribution artifacts
[group('dist')]
dist-all: release dist-tarball dist-checksums

# Build AUR package locally
[group('dist')]
[linux]
dist-aur:
    cd packaging/aur && makepkg -si

# Build Flatpak locally
[group('dist')]
[linux]
dist-flatpak:
    flatpak-builder --user --install build-flatpak packaging/flatpak/dev.tinyland.RemoteJuggler.yml

# Test install script (dry run)
[group('dist')]
dist-test-install:
    ./scripts/install.sh --help

# =============================================================================
# OpenTofu Infrastructure
# =============================================================================

# Initialize OpenTofu (download providers, connect state backend)
[group('tofu')]
tofu-init:
    deploy/tofu/apply.sh init

# Preview infrastructure changes
[group('tofu')]
tofu-plan:
    deploy/tofu/apply.sh plan

# Apply infrastructure changes
[group('tofu')]
tofu-apply:
    deploy/tofu/apply.sh apply

# Destroy all managed infrastructure
[group('tofu')]
tofu-destroy:
    deploy/tofu/apply.sh destroy

# Show current infrastructure outputs
[group('tofu')]
tofu-output:
    deploy/tofu/apply.sh output

# =============================================================================
# Campaigns
# =============================================================================

# Run a specific campaign by ID
[group('campaigns')]
campaign-run id:
    cd test/campaigns/runner && go run . --campaigns-dir=.. --campaign={{id}} --gateway-url=${RJ_GATEWAY_URL:-https://rj-gateway:443}

# List campaigns from the registry
[group('campaigns')]
campaign-list:
    @cat test/campaigns/index.json | python3 -c "import json,sys; idx=json.load(sys.stdin); [print(f'  {k}: enabled={v[\"enabled\"]}') for k,v in idx['campaigns'].items()]"

# Run all due campaigns once (for testing)
[group('campaigns')]
campaign-once:
    cd test/campaigns/runner && go run . --campaigns-dir=.. --once --gateway-url=${RJ_GATEWAY_URL:-https://rj-gateway:443}

# Build campaign runner binary
[group('campaigns')]
campaign-build:
    cd test/campaigns/runner && go build -o ../../../target/release/campaign-runner .

# Run campaign runner tests
[group('campaigns')]
campaign-test:
    cd test/campaigns/runner && go test -v ./...

# Scale HexStrike agent (0=dormant, 1=active)
[group('campaigns')]
campaign-scale-hexstrike replicas="0":
    kubectl scale deploy/hexstrike-agent -n fuzzy-dev --replicas={{replicas}}

# =============================================================================
# CI Helpers
# =============================================================================

# Run CI checks locally
[group('ci')]
ci: lint test-all

# Run ALL tests (unified entry point for CI)
[group('ci')]
test-all-ci: lint
    @echo "=== Running Chapel unit tests ==="
    just test || true
    @echo ""
    @echo "=== Running Bazel tests (Rust/Go/C/Swift) ==="
    bazelisk test //gtk-gui:... //tray/...:... //pinentry:... --test_tag_filters=-hardware || true
    @echo ""
    @echo "=== Running E2E tests (pytest) ==="
    pytest test/e2e/ -m "not tpm and not secure_enclave and not yubikey and not hardware" -v || true
    @echo ""
    @echo "=== CI test run complete ==="

# Run full Bazel test suite with E2E
[group('ci')]
bazel-test-full:
    bazelisk test //... --test_tag_filters=-hardware

# Run all tests including hardware tests
[group('ci')]
test-all-hardware: lint
    @echo "=== Running all tests including hardware ==="
    just test || true
    bazelisk test //... || true
    pytest test/e2e/ -v || true

# Simulate GitLab CI
[group('ci')]
ci-simulate:
    @echo "Running CI simulation..."
    just lint
    just test
    just test-integration
    just hsm-test
    just gui-test || true
    @echo "CI simulation complete"
