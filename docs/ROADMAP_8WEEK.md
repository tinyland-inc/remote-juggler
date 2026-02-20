# RemoteJuggler 8-Week Implementation Roadmap

**Created**: 2026-02-01
**Branch**: `sid/TPM-SE` (Trusted Workstation Mode)
**Goal**: Production-ready e2e testing, Bazel/Just adoption, bootstrap workflow, and distribution

---

## Executive Summary

This roadmap addresses critical gaps identified through comprehensive research:

| Area | Current State | Target State |
|------|---------------|--------------|
| **Build System** | Just + Nix | Just entrypoint + Bazel (Rust/Go/C) + Nix (Chapel) |
| **Testing** | Fragmented, 40% coverage | Unified, 85%+ coverage with e2e |
| **GUI Testing** | GTK minimal, Tray zero | Full UI automation |
| **HSM Testing** | Manual on hardware | CI with swtpm, SE mocks |
| **Distribution** | Manual binaries | Signed packages, Homebrew |
| **Bootstrap** | Implicit | `just setup` wizard |

---

## Research Findings Summary

### Critical Discoveries

1. **Bazel + Chapel**: No `rules_chapel` exists. Creating custom rules = 2-4 weeks. **Decision**: Use Bazel for Rust/Go/C/Swift only; keep Nix+Just for Chapel.

2. **Pinentry Implementation**: 95% complete (1,170 lines Python + 3,000+ lines C). Full Assuan protocol, TPM/SE backends working.

3. **GUI Testing Gap**:
   - GTK GUI: Has proptest but zero UI interaction tests
   - macOS Tray: ZERO tests
   - Linux Tray: ZERO tests

4. **E2E Tests Not in CI**: pytest suite exists (`test/e2e/`) but not wired into `.gitlab-ci.yml`

5. **No YubiKey Simulator**: Must use abstraction + physical hardware for full testing

6. **SE Cannot Be Virtualized**: Cloud CI cannot test Secure Enclave; need self-hosted Mac runner

### Files Touched by RemoteJuggler

| Category | Paths | Access |
|----------|-------|--------|
| **Configuration** | `~/.config/remote-juggler/config.json` | R/W |
| **State** | `~/.config/remote-juggler/state.json` | R/W |
| **GPG Agent** | `~/.gnupg/gpg-agent.conf` | R/W (with backup) |
| **TPM Sealed** | `~/.config/remote-juggler/hsm/tpm/*.sealed` | R/W |
| **SE Keys** | Keychain (service: `remote-juggler.hsm.pin`) | R/W |
| **SSH Config** | `~/.ssh/config` | Read-only |
| **Git Config** | `~/.gitconfig` | Read-only |
| **Logs** | `~/.cache/remote-juggler/pinentry.log` | Write |

---

## Week-by-Week Plan

### Week 1: Just Entrypoint & Project Structure

**Goal**: Unified developer experience via `just` command runner

#### Deliverables

1. **Create `justfile`** at project root:
   ```just
   # RemoteJuggler Development Commands
   set dotenv-load
   set export

   default:
       @just --list

   # Groups: dev, test, build, nix, hsm, gui, release
   ```

2. **Recipe Groups**:
   - `dev`: `shell`, `chapel-shell`, `build`, `watch`
   - `test`: `test`, `test-integration`, `test-e2e`, `test-all`
   - `build`: `release`, `release-static`, `cross-compile`
   - `nix`: `nix-build`, `nix-check`, `nix-update`, `nix-gc`
   - `hsm`: `hsm-build`, `hsm-test`, `hsm-install`
   - `gui`: `gui-build`, `gui-run`, `gui-test` (Linux only)
   - `release`: `tag`, `artifacts`, `publish`

3. **Platform-Specific Recipes**:
   ```just
   [linux]
   chapel-shell:
       nix develop .#chapel

   [macos]
   chapel-shell:
       @echo "Using system Chapel (Homebrew)"
   ```

4. **Bootstrap Recipe**:
   ```just
   setup:
       @echo "Setting up RemoteJuggler development environment..."
       just deps
       just build
       just test
       @echo "Run 'just --list' to see available commands"
   ```

#### Files Created
- `justfile` (root)
- `nix.just` (module)
- `test.just` (module)

---

### Week 2: Bazel Foundation (Rust, Go, C)

**Goal**: Bazel for well-supported languages; Nix for Chapel

#### Deliverables

1. **MODULE.bazel** (Bzlmod):
   ```python
   module(name = "remote_juggler", version = "2.0.0")

   bazel_dep(name = "rules_rust", version = "0.54.1")
   bazel_dep(name = "rules_go", version = "0.50.1")
   bazel_dep(name = "rules_swift", version = "2.2.3")
   bazel_dep(name = "rules_cc", version = "0.0.10")
   bazel_dep(name = "rules_nixpkgs_core", version = "0.12.0")
   ```

2. **BUILD.bazel files**:
   - `gtk-gui/BUILD.bazel` (Rust + GTK4)
   - `tray/darwin/BUILD.bazel` (Swift)
   - `tray/linux/BUILD.bazel` (Go)
   - `pinentry/BUILD.bazel` (C library)

3. **Just + Bazel Integration**:
   ```just
   [group('bazel')]
   bazel-build:
       bazelisk build //gtk-gui:remote-juggler-gui //tray/linux:tray

   [group('bazel')]
   bazel-test:
       bazelisk test //...
   ```

4. **Hybrid Build Strategy**:
   - Chapel CLI: `nix build .#remote-juggler`
   - GUI/Tray/HSM: `bazelisk build //...`
   - Unified: `just build-all`

#### Files Created
- `MODULE.bazel`
- `.bazelrc`
- `BUILD.bazel` (root, gtk-gui, tray/darwin, tray/linux, pinentry)
- `bazel.just` (module)

---

### Week 3: E2E Test Infrastructure

**Goal**: Unified test orchestration with pytest fixtures and swtpm

#### Deliverables

1. **Enhanced pytest fixtures** (`test/e2e/conftest.py`):
   ```python
   @pytest.fixture(scope="session")
   def isolated_gpg_environment(tmp_path_factory):
       """Session-wide GPG with test keys."""
       ...

   @pytest.fixture
   def swtpm_environment(tmp_path):
       """Start swtpm for TPM testing."""
       ...
   ```

2. **Test markers** (`pytest.ini`):
   ```ini
   markers =
       gpg: tests requiring GPG
       tpm: tests requiring TPM/swtpm
       secure_enclave: tests requiring macOS SE
       yubikey: tests requiring physical YubiKey
       hardware: tests requiring physical hardware
   ```

3. **swtpm Docker image** (`ci/docker/swtpm/Dockerfile`):
   ```dockerfile
   FROM debian:bookworm
   RUN apt-get update && apt-get install -y swtpm swtpm-tools tpm2-tools
   COPY entrypoint.sh /
   ENTRYPOINT ["/entrypoint.sh"]
   ```

4. **CI Integration** (`.gitlab-ci.yml`):
   ```yaml
   test:e2e-gpg:
     stage: test
     image: python:3.12
     script:
       - pip install pytest
       - pytest test/e2e/ -v -m gpg

   test:e2e-tpm:
     stage: test
     image: $CI_REGISTRY_IMAGE/swtpm:latest
     script:
       - pytest test/e2e/ -v -m tpm
   ```

5. **Just recipes**:
   ```just
   [group('test')]
   test-e2e:
       pytest test/e2e/ -v

   [group('test')]
   test-e2e-gpg:
       pytest test/e2e/ -v -m gpg

   [group('test')]
   test-e2e-tpm:
       pytest test/e2e/ -v -m tpm
   ```

#### Files Created/Modified
- `test/e2e/conftest.py` (enhanced)
- `test/e2e/fixtures/gpg.py`
- `test/e2e/fixtures/tpm.py`
- `ci/docker/swtpm/Dockerfile`
- `pytest.ini`

---

### Week 4: GUI Test Automation

**Goal**: UI tests for GTK GUI and tray apps

#### Deliverables

1. **GTK GUI Tests** (`gtk-gui/tests/`):
   - Use `gtk4::test` utilities
   - Window lifecycle tests
   - Identity list population tests
   - Switch identity UI flow
   - Screenshot comparison (optional)

2. **macOS Tray Tests** (`tray/darwin/Tests/`):
   ```swift
   import XCTest
   @testable import RemoteJugglerTray

   final class IdentityManagerTests: XCTestCase {
       func testLoadIdentities() throws {
           let manager = IdentityManager()
           // Test with mock config
       }
   }
   ```

3. **Linux Tray Tests** (`tray/linux/main_test.go`):
   ```go
   func TestLoadConfig(t *testing.T) {
       // Mock config file
       // Test identity loading
   }

   func TestSwitchIdentity(t *testing.T) {
       // Mock CLI execution
       // Verify state change
   }
   ```

4. **Bazel test targets**:
   ```python
   # gtk-gui/BUILD.bazel
   rust_test(
       name = "gui_test",
       crate = ":remote-juggler-gui",
       deps = ["@rules_rust//tools/runfiles"],
   )

   # tray/darwin/BUILD.bazel
   swift_test(
       name = "tray_darwin_test",
       srcs = glob(["Tests/**/*.swift"]),
   )

   # tray/linux/BUILD.bazel
   go_test(
       name = "tray_linux_test",
       srcs = ["main_test.go"],
       embed = [":tray_lib"],
   )
   ```

5. **CI with Xvfb**:
   ```yaml
   test:gtk-gui-e2e:
     stage: test
     image: rust:latest
     before_script:
       - apt-get install -y xvfb libgtk-4-dev libadwaita-1-dev
     script:
       - xvfb-run -a bazelisk test //gtk-gui:gui_test
   ```

#### Files Created
- `gtk-gui/tests/integration_test.rs`
- `tray/darwin/Tests/IdentityManagerTests.swift`
- `tray/darwin/Package.swift` (add test target)
- `tray/linux/main_test.go`

---

### Week 5: Bootstrap & Setup Wizard

**Goal**: First-run experience that configures GPG, imports identities, sets up HSM

#### Deliverables

1. **Setup Command** (`src/remote_juggler/Setup.chpl`):
   ```chapel
   proc setupWizard() {
       // 1. Detect existing SSH hosts → import as identities
       // 2. Detect GPG keys → associate with identities
       // 3. Detect YubiKey → offer TW mode
       // 4. Configure gpg-agent if needed
       // 5. Write config.json
   }
   ```

2. **CLI Commands**:
   ```bash
   remote-juggler setup              # Interactive wizard
   remote-juggler setup --auto       # Auto-detect everything
   remote-juggler setup --import-ssh # Import SSH hosts only
   remote-juggler setup --import-gpg # Import GPG keys only
   ```

3. **MCP Tools**:
   ```json
   {
     "name": "juggler_setup",
     "description": "Run first-time setup wizard",
     "inputSchema": {
       "properties": {
         "mode": {"enum": ["interactive", "auto", "import-ssh", "import-gpg"]}
       }
     }
   }
   ```

4. **Config Schema Extension** (`packaging/schemas/config.json`):
   ```json
   {
     "setupCompleted": true,
     "setupVersion": "2.0.0",
     "setupDate": "2026-02-01T00:00:00Z",
     "detectedSources": {
       "sshConfig": true,
       "gitConfig": true,
       "gpgKeys": ["ABCD1234"],
       "yubiKey": "12345678"
     }
   }
   ```

5. **Just recipe**:
   ```just
   [group('dev')]
   setup:
       ./target/release/remote-juggler setup --auto
   ```

#### Files Created
- `src/remote_juggler/Setup.chpl`
- `packaging/schemas/config.json` (updated)
- `docs/FIRST_TIME_SETUP.md`

---

### Week 6: Distribution & Signing

**Goal**: Signed packages for macOS and Linux

#### Deliverables

1. **macOS Code Signing** (enhance existing CI):
   - Developer ID Application certificate
   - Developer ID Installer certificate
   - Notarization with stapling
   - DMG with background image

2. **macOS Entitlements** (`packaging/macos/entitlements.plist`):
   ```xml
   <key>keychain-access-groups</key>
   <array>
       <string>$(AppIdentifierPrefix)dev.tinyland.remote-juggler</string>
   </array>
   ```

3. **Linux Packages** (enhance FPM):
   - RPM with proper dependencies (`tpm2-tss`)
   - DEB with proper dependencies
   - Arch PKGBUILD with AUR submission

4. **Homebrew Tap** (`homebrew-tools/Formula/remote-juggler.rb`):
   ```ruby
   class RemoteJuggler < Formula
     desc "Backend-agnostic git identity management"
     homepage "https://gitlab.com/tinyland/projects/remote-juggler"
     version "2.0.0"

     on_macos do
       if Hardware::CPU.arm?
         url "...darwin-arm64.tar.gz"
         sha256 "..."
       else
         url "...darwin-amd64.tar.gz"
         sha256 "..."
       end
     end

     on_linux do
       url "...linux-amd64.tar.gz"
       sha256 "..."
     end

     def install
       bin.install "remote-juggler"
       bash_completion.install "completions/bash" => "remote-juggler"
       zsh_completion.install "completions/zsh" => "_remote-juggler"
     end
   end
   ```

5. **Linux udev Rules** (`packaging/linux/99-remote-juggler.rules`):
   ```
   # TPM access for remote-juggler users
   KERNEL=="tpm[0-9]*", MODE="0660", GROUP="tss"
   KERNEL=="tpmrm[0-9]*", MODE="0660", GROUP="tss"
   ```

6. **systemd User Service** (`packaging/linux/remote-juggler.service`):
   ```ini
   [Unit]
   Description=RemoteJuggler Identity Manager
   After=gpg-agent.service

   [Service]
   Type=simple
   ExecStart=/usr/bin/remote-juggler --mode=daemon
   Restart=on-failure

   [Install]
   WantedBy=default.target
   ```

#### Files Created
- `packaging/macos/entitlements.plist`
- `packaging/macos/Info.plist`
- `packaging/linux/99-remote-juggler.rules`
- `packaging/linux/remote-juggler.service`
- `packaging/linux/post-install.sh` (enhanced)
- `homebrew-tools/Formula/remote-juggler.rb`

---

### Week 7: HSM E2E & Hardware Testing

**Goal**: Complete HSM test coverage including physical hardware

#### Deliverables

1. **swtpm CI Integration** (Week 3 foundation):
   - All TPM tests run in CI with swtpm
   - PCR binding tests
   - Seal/unseal lifecycle tests

2. **SE Mock for CI**:
   ```c
   // hsm_darwin_mock.c - For CI without SE
   int hsm_available() {
       if (getenv("REMOTE_JUGGLER_MOCK_SE")) {
           return HSM_STUB;
       }
       // Real SE detection
   }
   ```

3. **Physical Hardware Test Runner**:
   - Self-hosted GitLab runner on Mac Mini (SE tests)
   - Self-hosted runner with YubiKey USB passthrough
   - Manual trigger only (`when: manual`)

4. **E2E Test Scenarios**:
   ```python
   @pytest.mark.tpm
   def test_pin_store_retrieve_cycle(swtpm_env):
       """Test complete PIN lifecycle with TPM."""

   @pytest.mark.tpm
   def test_pcr_binding_prevents_unseal(swtpm_env):
       """Verify PCR change blocks unseal."""

   @pytest.mark.secure_enclave
   @pytest.mark.hardware
   def test_se_biometric_prompt(macos_runner):
       """Test Touch ID integration."""
   ```

5. **Integration Test Dashboard** (GitLab CI artifacts):
   - Test results as JUnit XML
   - Coverage reports
   - HSM status summary

#### Files Created/Modified
- `test/e2e/test_hsm_tpm.py`
- `test/e2e/test_hsm_se.py`
- `pinentry/hsm_darwin_mock.c`
- `.gitlab-ci.yml` (hardware runner jobs)

---

### Week 8: Documentation, Polish & Release

**Goal**: Production-ready release with comprehensive documentation

#### Deliverables

1. **User Documentation**:
   - `docs/GETTING_STARTED.md` - 5-minute quickstart
   - `docs/TRUSTED_WORKSTATION_SETUP.md` - Complete TW guide
   - `docs/TROUBLESHOOTING.md` - Common issues
   - `docs/SECURITY.md` - Security model explanation

2. **Developer Documentation**:
   - `docs/ARCHITECTURE.md` - System overview
   - `docs/BUILDING.md` - Build instructions with Just/Bazel
   - `docs/TESTING.md` - Test suite guide
   - `docs/CONTRIBUTING.md` - Contribution guidelines

3. **Man Pages**:
   - `remote-juggler(1)` - Main CLI
   - `remote-juggler-config(5)` - Configuration format
   - `pinentry-remotejuggler(1)` - Custom pinentry

4. **Shell Completions**:
   - `completions/bash/remote-juggler`
   - `completions/zsh/_remote-juggler`
   - `completions/fish/remote-juggler.fish`

5. **Release Automation**:
   ```just
   [group('release')]
   release version:
       @echo "Releasing v{{version}}..."
       just test-all
       just release-artifacts
       just tag {{version}}
       just publish
   ```

6. **Final CI Pipeline**:
   - All tests passing (no `allow_failure` on critical paths)
   - Signed artifacts for all platforms
   - Homebrew tap auto-update
   - GitLab Pages with MkDocs

---

## Success Metrics

| Metric | Week 1 | Week 8 |
|--------|--------|--------|
| Test Coverage | ~40% | 85%+ |
| GUI Tests | 0 | 50+ |
| E2E Tests in CI | 0 | All |
| Build Commands | `just ...` | `just ...` |
| Distribution | Manual | Homebrew + packages |
| Documentation | Sparse | Comprehensive |
| CI `allow_failure` | 12 jobs | 2 (hardware only) |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Bazel Chapel rules too complex | Keep Nix+Just for Chapel; Bazel for others |
| SE testing impossible in cloud | Self-hosted runner + mocking for CI |
| YubiKey simulation missing | Interface abstraction + manual hardware tests |
| Breaking changes during refactor | Feature flags, gradual rollout |

---

## Appendix: Agent IDs for Continuation

| Research Area | Agent ID |
|---------------|----------|
| Config/Integration | `a3661a7` |
| GUI/E2E Testing | `a171a8c` |
| Permissions/Distribution | `aa14aae` |
| Bazel Integration | `a0891ae` |
| Just Task Runner | `aebb32d` |
| GPG/HSM E2E Testing | `a8f15a8` |
| Pinentry Deep Dive | `a4cdfdb` |

---

## Next Steps

1. **Immediate**: Create `justfile` with basic recipes
2. **This Week**: Set up Bazel for gtk-gui
3. **Ongoing**: Wire E2E tests into CI
4. **Before Release**: Full documentation pass
