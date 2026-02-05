# RemoteJuggler Makefile
# Local development and user-wide installation

.PHONY: all build release test lint check clean deps install install-dev \
        uninstall install-completions install-claude install-mcp \
        mcp acp help info hsm hsm-clean \
        test-integration test-integration-tws test-integration-tws-tap test-all

# Installation paths
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
MANDIR ?= $(PREFIX)/share/man/man1
COMPDIR_BASH ?= $(HOME)/.local/share/bash-completion/completions
COMPDIR_ZSH ?= $(HOME)/.zsh/completions
COMPDIR_FISH ?= $(HOME)/.config/fish/completions

# Config paths
CONFIG_DIR ?= $(HOME)/.config/remote-juggler
CLAUDE_DIR ?= $(HOME)/.claude

# Binary name
BINARY = remote-juggler
MASON_TARGET = target/release/remote_juggler

# Chapel compiler flags
# --permit-unhandled-module-errors: Allow prototype-style error handling
# (unhandled throwing calls halt at runtime instead of compile-time errors)
# Note: prototype modules are used in the code for this purpose
CHPL_FLAGS = -M src/remote_juggler

# Platform detection
UNAME_S := $(shell uname -s)

# =============================================================================
# HSM Library Configuration
# =============================================================================

# HSM library paths
HSM_DIR = pinentry
HSM_HEADER = $(HSM_DIR)/hsm.h
ifeq ($(UNAME_S),Darwin)
  HSM_LIB = $(HSM_DIR)/libhsm_remotejuggler.dylib
  HSM_LIB_EXT = dylib
else
  HSM_LIB = $(HSM_DIR)/libhsm_remotejuggler.so
  HSM_LIB_EXT = so
endif

# Check if HSM library exists (for conditional linking)
HSM_EXISTS := $(shell test -f $(HSM_LIB) && echo yes || echo no)

# HSM-related Chapel flags
# -I for header include path, -L for library path, -l for library name
HSM_CHPL_FLAGS = --ccflags="-I$(CURDIR)/$(HSM_DIR)"
HSM_LINK_FLAGS = --ldflags="-L$(CURDIR)/$(HSM_DIR) -lhsm_remotejuggler -Wl,-rpath,$(CURDIR)/$(HSM_DIR)"

# Platform-specific linker flags for macOS Security.framework
ifeq ($(UNAME_S),Darwin)
  CHPL_LDFLAGS = --ldflags="-framework Security -framework CoreFoundation"
  # macOS needs additional flags for HSM library
  HSM_LINK_FLAGS += --ldflags="-framework Security -framework CoreFoundation"
else
  CHPL_LDFLAGS =
  # Linux may need TPM2-TSS libraries if available
  TPM_AVAILABLE := $(shell pkg-config --exists tss2-esys 2>/dev/null && echo yes || echo no)
  ifeq ($(TPM_AVAILABLE),yes)
    HSM_LINK_FLAGS += --ldflags="$(shell pkg-config --libs tss2-esys tss2-rc tss2-tctildr)"
  endif
endif

# Combine HSM flags when library is available
ifeq ($(HSM_EXISTS),yes)
  CHPL_HSM_FLAGS = $(HSM_CHPL_FLAGS) $(HSM_LINK_FLAGS) -sHSM_NATIVE_AVAILABLE=true
else
  CHPL_HSM_FLAGS = -sHSM_NATIVE_AVAILABLE=false
endif

# Default target
all: lint build test

# =============================================================================
# HSM Library Target
# =============================================================================

# Build HSM library (optional - build continues without it)
hsm:
	@echo "Building HSM library..."
	@$(MAKE) -C $(HSM_DIR) all || { \
		echo ""; \
		echo "WARNING: HSM library build failed or TPM2-TSS not available."; \
		echo "         Building without native HSM support (stub mode)."; \
		echo ""; \
	}

# Clean HSM library artifacts
hsm-clean:
	@$(MAKE) -C $(HSM_DIR) clean

# =============================================================================
# Build Targets
# =============================================================================

# Build debug version (with HSM if available)
build: hsm
	@echo "Building RemoteJuggler (debug)..."
	@mkdir -p target/debug
	$(eval HSM_EXISTS := $(shell test -f $(HSM_LIB) && echo yes || echo no))
	$(eval CHPL_HSM_FLAGS := $(if $(filter yes,$(HSM_EXISTS)),$(HSM_CHPL_FLAGS) $(HSM_LINK_FLAGS) -sHSM_NATIVE_AVAILABLE=true,-sHSM_NATIVE_AVAILABLE=false))
	@if [ "$(HSM_EXISTS)" = "yes" ]; then \
		echo "  [HSM] Native HSM library found, linking..."; \
	else \
		echo "  [HSM] Native HSM library not found, using stub implementation..."; \
	fi
	@chpl $(CHPL_FLAGS) $(CHPL_HSM_FLAGS) $(CHPL_LDFLAGS) -o target/debug/$(BINARY) src/remote_juggler.chpl

# Build release version (optimized, with HSM if available)
release: hsm
	@echo "Building RemoteJuggler (release)..."
	@mkdir -p target/release
	$(eval HSM_EXISTS := $(shell test -f $(HSM_LIB) && echo yes || echo no))
	$(eval CHPL_HSM_FLAGS := $(if $(filter yes,$(HSM_EXISTS)),$(HSM_CHPL_FLAGS) $(HSM_LINK_FLAGS) -sHSM_NATIVE_AVAILABLE=true,-sHSM_NATIVE_AVAILABLE=false))
	@if [ "$(HSM_EXISTS)" = "yes" ]; then \
		echo "  [HSM] Native HSM library found, linking..."; \
	else \
		echo "  [HSM] Native HSM library not found, using stub implementation..."; \
	fi
	@chpl $(CHPL_FLAGS) $(CHPL_HSM_FLAGS) $(CHPL_LDFLAGS) --fast -o $(MASON_TARGET) src/remote_juggler.chpl

# =============================================================================
# Test & Lint Targets
# =============================================================================

# Run unit tests
test:
	@echo "Running tests..."
	@./scripts/run-tests.sh

# Run chplcheck linter
lint:
	@echo "Running chplcheck linter..."
	@./scripts/run-chplcheck.sh

# Run both lint and test
check: lint test

# Run integration tests for Trusted Workstation
test-integration-tws: build
	@echo "Running Trusted Workstation integration tests..."
	@./test/integration/test_trusted_workstation.sh --binary target/debug/$(BINARY)

# Run integration tests with TAP output (for CI)
test-integration-tws-tap: build
	@./test/integration/test_trusted_workstation.sh --binary target/debug/$(BINARY) --tap

# Run all integration tests
test-integration: test-integration-tws

# Run all tests (unit + integration)
test-all: test test-integration

# =============================================================================
# Installation Targets
# =============================================================================

# Full user-wide installation
install: release install-binary install-config install-completions install-claude
	@echo ""
	@echo "$(BINARY) installed successfully!"
	@echo ""
	@echo "Run '$(BINARY) --help' to get started"
	@echo "Run 'make info' to see installation paths"

# Install from source (development)
install-dev: build
	@echo "Installing development build..."
	@mkdir -p $(BINDIR)
	@cp target/debug/remote_juggler $(BINDIR)/$(BINARY)
	@chmod +x $(BINDIR)/$(BINARY)
	@echo "Installed to $(BINDIR)/$(BINARY)"

# Install binary only
install-binary: release
	@echo "Installing binary to $(BINDIR)..."
	@mkdir -p $(BINDIR)
	@cp $(MASON_TARGET) $(BINDIR)/$(BINARY)
	@chmod +x $(BINDIR)/$(BINARY)
	@echo "Binary installed: $(BINDIR)/$(BINARY)"

# Initialize configuration
install-config:
	@echo "Initializing configuration..."
	@mkdir -p $(CONFIG_DIR)
	@if [ ! -f $(CONFIG_DIR)/config.json ]; then \
		echo '{"version":"2.0.0","identities":{},"settings":{"defaultProvider":"gitlab","autoDetect":true,"useKeychain":true,"gpgSign":true}}' > $(CONFIG_DIR)/config.json; \
		echo "Created $(CONFIG_DIR)/config.json"; \
	else \
		echo "Config already exists at $(CONFIG_DIR)/config.json"; \
	fi

# Install shell completions
install-completions: release
	@echo "Installing shell completions..."
	@mkdir -p $(COMPDIR_BASH) $(COMPDIR_ZSH) $(COMPDIR_FISH)
	@$(BINDIR)/$(BINARY) --completions=bash > $(COMPDIR_BASH)/$(BINARY) 2>/dev/null || \
		./scripts/generate-completions.sh bash > $(COMPDIR_BASH)/$(BINARY)
	@$(BINDIR)/$(BINARY) --completions=zsh > $(COMPDIR_ZSH)/_$(BINARY) 2>/dev/null || \
		./scripts/generate-completions.sh zsh > $(COMPDIR_ZSH)/_$(BINARY)
	@$(BINDIR)/$(BINARY) --completions=fish > $(COMPDIR_FISH)/$(BINARY).fish 2>/dev/null || \
		./scripts/generate-completions.sh fish > $(COMPDIR_FISH)/$(BINARY).fish
	@echo "Completions installed for bash, zsh, and fish"

# Install Claude Code integration
install-claude:
	@echo "Installing Claude Code integration..."
	@mkdir -p $(CLAUDE_DIR)/commands $(CLAUDE_DIR)/skills/git-identity
	@if [ -d .claude/commands ]; then \
		cp .claude/commands/*.md $(CLAUDE_DIR)/commands/ 2>/dev/null || true; \
	fi
	@if [ -d .claude/skills/git-identity ]; then \
		cp .claude/skills/git-identity/*.md $(CLAUDE_DIR)/skills/git-identity/ 2>/dev/null || true; \
	fi
	@echo "Claude Code slash commands and skills installed"

# Install MCP config to current project
install-mcp:
	@echo "Installing .mcp.json to current directory..."
	@if [ -f .mcp.json ]; then \
		echo "Warning: .mcp.json already exists"; \
	else \
		echo '{"mcpServers":{"remote-juggler":{"command":"$(BINARY)","args":["--mode=mcp"]}}}' > .mcp.json; \
		echo "Created .mcp.json"; \
	fi

# =============================================================================
# Uninstall Target
# =============================================================================

uninstall:
	@echo "Uninstalling RemoteJuggler..."
	@rm -f $(BINDIR)/$(BINARY)
	@rm -f $(COMPDIR_BASH)/$(BINARY)
	@rm -f $(COMPDIR_ZSH)/_$(BINARY)
	@rm -f $(COMPDIR_FISH)/$(BINARY).fish
	@echo "Binary and completions removed"
	@echo ""
	@echo "Config preserved at $(CONFIG_DIR)"
	@echo "Claude integration preserved at $(CLAUDE_DIR)"
	@echo "Remove manually if desired"

# =============================================================================
# Utility Targets
# =============================================================================

# Fetch dependencies
deps:
	@echo "Fetching Mason dependencies..."
	@mkdir -p $(HOME)/.mason/registry
	@if ! grep -q "tinyland" $(HOME)/.mason/registry/mason-registry.toml 2>/dev/null; then \
		echo '[[registry]]' >> $(HOME)/.mason/registry/mason-registry.toml; \
		echo 'name = "tinyland"' >> $(HOME)/.mason/registry/mason-registry.toml; \
		echo 'source = "https://github.com/Jesssullivan/mason-registry"' >> $(HOME)/.mason/registry/mason-registry.toml; \
		echo 'branch = "sid"' >> $(HOME)/.mason/registry/mason-registry.toml; \
		echo "Added tinyland registry"; \
	fi
	@mason update || echo "Mason update skipped"

# Clean build artifacts
clean: hsm-clean
	@echo "Cleaning build artifacts..."
	@rm -rf target/
	@rm -f test-results.xml
	@rm -f chplcheck-report.txt

# Deep clean (including Mason cache)
distclean: clean
	@rm -rf .mason/
	@rm -f Mason.lock

# Run MCP server mode
mcp: build
	@./target/debug/remote_juggler --mode=mcp

# Run ACP server mode
acp: build
	@./target/debug/remote_juggler --mode=acp

# Show installation info
info:
	@echo "RemoteJuggler Installation Info"
	@echo "================================"
	@echo ""
	@echo "Binary:       $(BINDIR)/$(BINARY)"
	@echo "Config:       $(CONFIG_DIR)/config.json"
	@echo ""
	@echo "Completions:"
	@echo "  Bash:       $(COMPDIR_BASH)/$(BINARY)"
	@echo "  Zsh:        $(COMPDIR_ZSH)/_$(BINARY)"
	@echo "  Fish:       $(COMPDIR_FISH)/$(BINARY).fish"
	@echo ""
	@echo "Claude Code:"
	@echo "  Commands:   $(CLAUDE_DIR)/commands/"
	@echo "  Skills:     $(CLAUDE_DIR)/skills/git-identity/"
	@echo ""
	@echo "Environment:"
	@echo "  PREFIX:     $(PREFIX)"
	@echo "  CONFIG_DIR: $(CONFIG_DIR)"
	@echo ""
	@if [ -x $(BINDIR)/$(BINARY) ]; then \
		echo "Status: Installed"; \
		$(BINDIR)/$(BINARY) --version 2>/dev/null || echo "  (version check not implemented)"; \
	else \
		echo "Status: Not installed"; \
	fi

# Show help
help:
	@echo "RemoteJuggler Development Commands"
	@echo "==================================="
	@echo ""
	@echo "Building:"
	@echo "  make build        Build debug version (includes HSM)"
	@echo "  make release      Build release version (optimized)"
	@echo "  make hsm          Build HSM library only"
	@echo ""
	@echo "Testing:"
	@echo "  make test                  Run unit tests"
	@echo "  make lint                  Run chplcheck linter"
	@echo "  make check                 Run lint + test"
	@echo "  make test-integration-tws  Run Trusted Workstation E2E tests"
	@echo "  make test-integration      Run all integration tests"
	@echo "  make test-all              Run unit + integration tests"
	@echo ""
	@echo "Installation:"
	@echo "  make install      Full user-wide installation"
	@echo "  make install-dev  Install debug build for development"
	@echo "  make uninstall    Remove installed files"
	@echo ""
	@echo "Components (called by 'make install'):"
	@echo "  make install-binary      Install binary only"
	@echo "  make install-config      Initialize config files"
	@echo "  make install-completions Install shell completions"
	@echo "  make install-claude      Install Claude Code integration"
	@echo "  make install-mcp         Create .mcp.json in current dir"
	@echo ""
	@echo "Utilities:"
	@echo "  make deps         Fetch Mason dependencies"
	@echo "  make clean        Remove build artifacts (including HSM)"
	@echo "  make hsm-clean    Remove HSM library artifacts only"
	@echo "  make distclean    Clean + remove Mason cache"
	@echo "  make mcp          Run MCP server mode"
	@echo "  make acp          Run ACP server mode"
	@echo "  make info         Show installation paths"
	@echo ""
	@echo "Variables (override with VAR=value):"
	@echo "  PREFIX            Install prefix (default: ~/.local)"
	@echo "  BINDIR            Binary directory (default: PREFIX/bin)"
	@echo "  CONFIG_DIR        Config directory (default: ~/.config/remote-juggler)"
	@echo ""
	@echo "HSM Support:"
	@echo "  Platform:         $(UNAME_S)"
ifeq ($(UNAME_S),Darwin)
	@echo "  Backend:          Secure Enclave / Keychain"
else
  ifeq ($(TPM_AVAILABLE),yes)
	@echo "  Backend:          TPM 2.0 (tss2-esys available)"
  else
	@echo "  Backend:          Stub (tss2-esys not found)"
  endif
endif
	@echo "  Library:          $(HSM_LIB)"
	@echo "  Status:           $(if $(filter yes,$(shell test -f $(HSM_LIB) && echo yes || echo no)),Built,Not built)"
