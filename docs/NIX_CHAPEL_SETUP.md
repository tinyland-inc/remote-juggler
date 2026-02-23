# Chapel Setup for Nix

This document explains how RemoteJuggler builds Chapel from source in the Nix environment.

## Overview

Chapel 2.7.0 is built from source using Nix's system LLVM 18. This produces native binaries on all platforms without requiring FHS sandboxing, bubblewrap, or Homebrew.

The approach is adapted from [twesterhout/nix-chapel](https://github.com/twesterhout/nix-chapel), which demonstrated that Chapel can be built with `CHPL_LLVM=system` pointing at Nix's LLVM.

## Quick Start

```bash
# Build RemoteJuggler (builds Chapel from source on first run, ~25 min)
nix build .#remote-juggler
./result/bin/remote-juggler --help

# Build just the Chapel compiler
nix build .#chapel
./result/bin/chpl --version

# Enter development shell (includes Chapel + Rust + Go toolchains)
nix develop
chpl --version
```

## How It Works

The derivation in `nix/chapel.nix`:

1. Takes the Chapel 2.7.0 source from the `chapel-src` flake input
2. Configures Chapel with `CHPL_LLVM=system`, pointing at Nix's LLVM 18.1.8
3. Patches M68k macro detection (Nix's LLVM excludes exotic backends)
4. Builds Chapel in-place with `make -j$NIX_BUILD_CORES`
5. Selectively copies build artifacts to `$out` (avoiding `/build/` path references)
6. Wraps the `chpl` binary with proper `CHPL_HOME` and compiler flags

### Key Build Settings

| Setting | Value | Reason |
|---------|-------|--------|
| `CHPL_LLVM` | `system` | Use Nix's pre-built LLVM (avoids 1-3hr bundled LLVM build) |
| `CHPL_LLVM_CONFIG` | `llvm-config` from `llvmPackages_18` | Points at LLVM 18.1.8 |
| `CHPL_RE2` | `bundled` | Simpler than wiring system re2 |
| `CHPL_GMP` | `bundled` | Simpler than wiring system gmp |
| `CHPL_TARGET_CPU` | `none` | Portable binaries |
| `CHPL_UNWIND` | `none` | Avoid libunwind dependency complexity |

### The M68k Patch

Nix's LLVM doesn't include exotic target backends (M68k, AArch64BE, etc.). Chapel's `util/chplenv/chpl_llvm.py` validates that all LLVM target macros are present, which fails. The fix disables this check:

```nix
substituteInPlace util/chplenv/chpl_llvm.py \
  --replace-warn 'if macro in out' 'if False'
```

This is the same approach used by `twesterhout/nix-chapel`. It should be upstreamed to Chapel.

## Available Packages

| Package | Description | Platforms |
|---------|-------------|-----------|
| `remote-juggler` | Main RemoteJuggler CLI binary | Linux, macOS |
| `chapel` | Chapel 2.7.0 compiler (from source) | Linux, macOS |
| `rj-gateway` | Go MCP gateway | Linux, macOS |
| `pinentry-remotejuggler` | HSM-backed pinentry | Linux, macOS |
| `remote-juggler-gui` | GTK4 GUI | Linux only |
| `chapel-fhs` | Legacy FHS wrapper (deprecated) | Linux only |

## Dev Shells

| Shell | Command | Description |
|-------|---------|-------------|
| `default` | `nix develop` | Full dev environment (Chapel + Rust + Go) |
| `chapel` | `nix develop .#chapel` | Chapel-only development |
| `tpm` | `nix develop .#tpm` | TPM/HSM development (Linux) |

## Using Custom Chapel Source

Override the Chapel source at build time:

```bash
# Use a custom Chapel fork/branch
nix build --override-input chapel-src github:jesssullivan/chapel/sid-nix-support .#remote-juggler

# Update flake.lock to pin a different Chapel source
nix flake lock --override-input chapel-src github:your-user/chapel/your-branch
```

## CI/CD Integration

### GitHub Actions

The Nix CI workflow (`.github/workflows/nix-ci.yml`) builds on all four platforms:
- Linux x86_64 (native)
- Linux aarch64 (QEMU emulation)
- macOS x86_64 (Intel runner)
- macOS aarch64 (Apple Silicon)

### Attic Binary Cache

Pre-built packages are cached at:
```
https://nix-cache.fuzzy-dev.tinyland.dev/tinyland
```

The cache is configured in `flake.nix`. First builds take ~25 min (Chapel compilation), but cached builds are instant.

## Build Times

| Component | Cold Build | Cached |
|-----------|-----------|--------|
| Chapel compiler | ~23 min | instant |
| RemoteJuggler CLI | ~1 min | instant |
| Go gateway | ~30 sec | instant |

## Troubleshooting

### Build takes a long time

Chapel compilation from source takes ~23 minutes. This is expected for cold builds. The Attic binary cache eliminates this for subsequent builds.

### "utf8-decoder.h not found"

This header-only library must be present in the Chapel installation. If you see this error after modifying `nix/chapel.nix`, ensure the installPhase includes:
```nix
cp -r third-party/utf8-decoder $out/third-party/
```

### "hsm.h not found"

Chapel's `HSM.chpl` module has `require "hsm.h"` which is always compiled. The RemoteJuggler build includes `-I$src/pinentry` to find this header.

### LLVM version mismatch

The derivation uses `llvmPackages_18` from nixpkgs 24.11. Chapel 2.7.0 supports LLVM 14-20. If you change the nixpkgs pin, you may need to adjust the LLVM version.

## Related Files

- `flake.nix` - Main flake with Chapel version pinning and package definitions
- `nix/chapel.nix` - Chapel from-source derivation
- `nix/chapel-fhs.nix` - Legacy FHS environment (deprecated, Linux only)
- `.github/workflows/nix-ci.yml` - GitHub Actions Nix CI
