# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-02-22

### Added

**Nix Build System**
- Chapel 2.7.0 built from source with system LLVM 18 (eliminates FHS/bubblewrap)
- Cross-platform Nix builds: Linux x86_64/aarch64, macOS x86_64/aarch64
- Nix CI jobs no longer require `continue-on-error`

**SOPS/KDBX Bidirectional Credential Sync**
- 4 new MCP tools: juggler_keys_sops_status, sops_ingest, sops_sync, sops_export
- 3 new CLI commands: keys sops-ingest, sops-sync, sops-export
- Bidirectional sync between SOPS-encrypted files and KeePassXC database
- Mock test fixtures for sops, age, and age-keygen binaries

**KeePassXC Credential Authority**
- Full KeePassXC integration with TPM/SE-backed auto-unlock
- 12 `keys` CLI commands: init, status, search, resolve, get, store, delete, list, ingest, crawl, discover, export
- Auto-discovery of environment variables, SSH keys, and .env files
- Fuzzy search with Levenshtein distance, word boundary, and substring matching

**MCP Gateway (rj-gateway)**
- Go HTTP/SSE proxy wrapping Chapel MCP server via embedded Tailscale (tsnet)
- Additive credential resolver: env > SOPS > KDBX > Setec precedence
- Setec secret server client with background polling and local cache
- Tailscale identity extraction, audit logging, and grants-based access control
- 5 gateway MCP tools: juggler_resolve_composite, setec_list, setec_get, setec_put, audit_log
- Local mode (`--listen=local`) for development without tailnet
- Dockerfile, Bazel target, Nix package, systemd service unit

**Agent Deployments**
- OpenClaw AI agent (K8s, Tailscale sidecar, Aperture routing)
- HexStrike pentest agent (K8s, dormant by default, results PVC)
- Claude Code lab integration (Home Manager module, local MCP config)
- OpenTofu IaC for full stack deployment on Civo K8s
- Tailscale ACL grants for reader/admin/ci-agent roles

**Expanded MCP Tools**
- 41 MCP tools (up from 13): 12 KeePassXC + 4 SOPS + 5 gateway + 20 identity/config/security
- KeePassXC MCP tools: juggler_keys_status, search, get, store, ingest_env, list, init, resolve, delete, crawl_env, discover, export
- SOPS MCP tools: juggler_keys_sops_status, sops_ingest, sops_sync, sops_export
- Gateway MCP tools: juggler_resolve_composite, setec_list, setec_get, setec_put, audit_log

**Distribution & Packaging**
- First public GitHub release with automated CI/CD pipeline
- .deb and .rpm packages via nfpm
- Nix flake with overlay and Home Manager module for declarative installation
- GitHub Pages documentation site
- Automated Homebrew SHA256 updates in release workflow
- install.sh auto-detects latest version from GitHub API
- npm package: `npx @tummycrypt/remote-juggler`
- Docker image: `ghcr.io/tinyland-inc/remote-juggler`
- Dynamic README artifact block generator

**Testing**
- 141+ E2E tests covering all MCP tools, installation, and multi-identity switching
- Comprehensive CI: 15 jobs across Chapel CLI, GTK GUI, Go tray, macOS, ARM64
- Release CI matrix groups for multi-platform builds

### Changed
- Bumped MCP protocol version to 2025-11-25
- install.sh downloads from GitHub Releases (primary) with GitLab fallback
- Migrated repository URLs to tinyland-inc/remote-juggler
- Release workflow collapsed into matrix groups

### Fixed
- Nix CI `result` path resolution
- swtpm test fixture (consecutive ports, tpm2_startup sequence)
- Documentation grounded in code reality (removed phantom tools, corrected field names)
- Install script rewritten for portable bare binaries (was broken with tar.gz)
- MCP tool tests require proper initialization handshake
- TPM tests skip gracefully when swtpm unavailable
- Multi-identity test fixtures use --no-gpg-sign
- Docker build uses chpl directly with apt-get update
- Portable binary CI with CHPL_TARGET_CPU=none

### Removed
- Dead code: GPGAgent module (1,229 lines), unused functions
- 3 phantom YubiKey tools from schema documentation (never existed in source)
- Homebrew tap references (tap repo doesn't exist)
- AUR and Flatpak references (not published)

## [2.0.0] - 2026-02-05

### Added

**Core Identity Management**
- Multi-provider git identity switching (GitLab, GitHub, Bitbucket, Azure, Codeberg)
- Automatic identity detection from repository remote URLs
- SSH host alias management with managed configuration blocks
- Git URL rewrite synchronization between SSH config and gitconfig

**MCP Server (Model Context Protocol)**
- 13 MCP tools for AI agent integration
- Protocol version 2025-11-25 compliance
- Tools: `juggler_list_identities`, `juggler_detect_identity`, `juggler_switch`, `juggler_status`, `juggler_validate`, `juggler_store_token`, `juggler_sync_config`, `juggler_gpg_status`, `juggler_pin_store`, `juggler_pin_clear`, `juggler_pin_status`, `juggler_security_mode`, `juggler_setup`

**Hardware Security (Trusted Workstation Mode)**
- TPM 2.0 integration for Linux (PIN sealed to PCR 7)
- Secure Enclave integration for macOS (ECIES with P-256)
- Custom pinentry for gpg-agent with HSM PIN retrieval
- Three security modes: maximum_security, developer_workflow, trusted_workstation

**GPG/YubiKey Integration**
- YubiKey detection and management via ykman
- Touch policy configuration (sig/enc/aut slots)
- PIN policy management (once/always)
- Hardware key status in MCP responses

**Platform Applications**
- GTK4/Libadwaita GUI for Linux desktops
- Go system tray for Linux with D-Bus singleton
- Swift MenuBarExtra tray for macOS
- Desktop notifications on identity switch

**Token Management**
- System keychain integration (macOS Security.framework, libsecret)
- Token expiration detection and renewal prompts
- Provider CLI authentication (glab, gh)

### Architecture

- Chapel 2.6+ for CLI core with MCP/ACP server
- Rust/GTK4 for Linux GUI
- Go for Linux system tray
- Swift/SwiftUI for macOS tray
- C FFI for TPM 2.0 and Secure Enclave
- Python for custom pinentry

### Documentation

- Comprehensive MCP tool schemas
- Architecture diagrams and data flow documentation
- Configuration schema reference
- Trusted Workstation setup guide

## [1.0.0] - REMOVED

Previous 1.0.0 changelog was from a different project and has been removed.
RemoteJuggler v2.0.0 is the first public release of the Chapel-based implementation.

---

[2.1.0]: https://github.com/tinyland-inc/remote-juggler/releases/tag/v2.1.0
[2.0.0]: https://gitlab.com/tinyland/projects/remote-juggler/-/releases/v2.0.0
