# Chapel Setup for Nix

This document explains how RemoteJuggler handles Chapel in the Nix environment.

## The Problem

Chapel 2.7 Ubuntu binaries were built against Ubuntu's LLVM 18, which includes all target backends (including exotic ones like M68k for Motorola 68000). Nix's LLVM 18 is optimized for smaller size and excludes these unused targets.

When using the standard `autoPatchelf` approach to make Ubuntu binaries work in Nix, Chapel tries to load LLVM symbols that don't exist:

```
undefined symbol: LLVMInitializeM68kAsmParser
```

## The Solution: FHS Environment

We use `pkgs.buildFHSEnv` to create an FHS-compatible sandbox where Chapel can run with its bundled dependencies. This approach:

1. Provides Ubuntu-like filesystem layout (`/lib`, `/usr/lib`, etc.)
2. Isolates Chapel from Nix's LLVM
3. Uses Chapel's bundled LLVM instead of Nix's

## Usage

### Development

Enter the Nix development shell:

```bash
nix develop
```

This gives you access to `chapel-fhs`, an FHS wrapper for Chapel. To compile:

```bash
# Enter the FHS environment
chapel-fhs

# Now you're in an FHS sandbox with Chapel available
chpl --version
make release
```

Or run commands directly:

```bash
chapel-fhs -c 'chpl --version'
chapel-fhs -c 'make release'
```

### Building with Nix

```bash
# Build the RemoteJuggler binary
nix build .#remote-juggler

# Build the Chapel FHS environment itself
nix build .#chapel-fhs
```

### Available Packages

| Package | Description |
|---------|-------------|
| `remote-juggler` | Main RemoteJuggler binary (built with FHS Chapel) |
| `chapel-fhs` | FHS wrapper for Chapel (enter with `chapel-fhs`) |
| `chapel-legacy` | Legacy autoPatchelf approach (may not work) |
| `pinentry-remotejuggler` | HSM-backed pinentry |
| `remote-juggler-gui` | GTK4 GUI (doesn't need Chapel) |

### Dev Shells

| Shell | Command | Description |
|-------|---------|-------------|
| `default` | `nix develop` | Full development environment |
| `chapel` | `nix develop .#chapel` | Chapel-only (uses FHS) |
| `tpm` | `nix develop .#tpm` | TPM/HSM development |

## How It Works

The FHS environment is created in `nix/chapel-fhs.nix`:

1. **Extract Chapel .deb**: The Ubuntu .deb package is extracted to a Nix store path
2. **Create FHS sandbox**: `buildFHSEnv` creates a filesystem with standard Linux paths
3. **Set up environment**: The `profile` sets `CHPL_HOME`, `PATH`, and other Chapel vars
4. **Bundle dependencies**: Required libs (glibc, zlib, etc.) are available in the FHS

When you run `chapel-fhs -c 'command'`, it:
1. Enters the FHS sandbox
2. Runs the profile script to set up Chapel
3. Executes your command
4. Exits the sandbox

## Troubleshooting

### "chpl: command not found"

Make sure you're inside the FHS environment:

```bash
chapel-fhs -c 'chpl --version'
# NOT: chpl --version (outside FHS)
```

### "undefined symbol" errors

This means you're trying to run Chapel outside the FHS sandbox. Always use `chapel-fhs`:

```bash
# Wrong - runs outside FHS
./result/bin/chpl test.chpl

# Correct - runs inside FHS
chapel-fhs -c 'chpl test.chpl'
```

### Build fails in CI

Check that the CI is using the FHS-based build. The `gitlab-nix.yml` should have:

```yaml
script:
  - nix build .#remote-juggler --print-build-logs
```

This automatically uses the FHS approach.

### "bwrap: setting up uid map: Permission denied"

The FHS environment uses `bubblewrap` for user namespace isolation. This requires
unprivileged user namespaces to be enabled on the host system.

**GitHub Actions**: User namespaces are not enabled by default on GitHub-hosted
runners. The Nix CI workflow marks these jobs as `continue-on-error: true`.
The main CI workflow (`ci.yml`) uses Chapel Docker images which work correctly.

**GitLab CI**: Depends on runner configuration. Docker executors may need
`--privileged` or the host must have `kernel.unprivileged_userns_clone=1`.

**Workarounds**:
1. Use the main CI workflow (`ci.yml`) which uses Chapel Docker images
2. Run Nix builds locally where user namespaces are typically available
3. Configure runners with user namespace support

## Chapel Sourcing Tiers

RemoteJuggler supports multiple Chapel sources for flexibility:

| Tier | Source | Platform | Use Case |
|------|--------|----------|----------|
| 1 | **FHS Environment** | Linux | Default - Ubuntu binaries in FHS sandbox |
| 2 | **System Chapel** | macOS | Homebrew passthrough |
| 3 | **Container** | CI/CD | Docker/Podman fallback |
| 4 | **Custom Fork** | Development | Build from custom Chapel source |

### Using Custom Chapel Fork

For Chapel development or testing patches:

```bash
# Override Chapel source at build time
nix build --override-input chapel-src github:jesssullivan/chapel/sid-nix-support .#remote-juggler

# Update flake.lock to use your fork
nix flake lock --override-input chapel-src github:your-user/chapel/your-branch
```

The `chapel-src` input is defined in `flake.nix` and defaults to the official Chapel 2.7.0 release.

## CI/CD Integration

### GitLab CI

Nix builds are configured in `ci/gitlab-nix.yml`. The builds:
- Use the `nixos/nix:2.28.3` image
- Build with `--print-build-logs` for debugging
- Push artifacts to Attic binary cache

### Attic Binary Cache

Pre-built packages are cached at:
```
https://nix-cache.fuzzy-dev.tinyland.dev/tinyland
```

The cache is automatically used (configured in `flake.nix`). First builds may be slow, but subsequent builds should be fast.

## Future Work

Long-term, we plan to:
1. Contribute Chapel packaging to nixpkgs upstream
2. Work with Chapel team to support Nix's LLVM (configure Chapel to not require M68k, AArch64BE, etc.)
3. Build Chapel from source with Nix's LLVM once upstream supports it

For now, the FHS approach provides a reliable workaround.

## Related Files

- `flake.nix` - Main Nix flake with Chapel version pinning
- `nix/chapel-fhs.nix` - FHS environment implementation
- `ci/gitlab-nix.yml` - GitLab CI Nix configuration
- `.github/workflows/nix.yml` - GitHub Actions Nix configuration
