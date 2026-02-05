# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[2.0.0]: https://gitlab.com/tinyland/projects/remote-juggler/-/releases/v2.0.0
