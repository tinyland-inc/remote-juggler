# Nix CI Setup for RemoteJuggler

This document describes how to configure the Nix-based CI workflow with Attic binary cache.

## Overview

The `nix-ci.yml` workflow provides:

- Reproducible builds using Nix flakes
- Multi-architecture support (x86_64 + aarch64)
- Multi-platform support (Linux + macOS)
- Binary caching via Attic for fast rebuilds

## Required GitHub Secrets

### ATTIC_TOKEN

The Attic authentication token for pushing build results to the cache.

**How to generate:**

1. Access your Attic server (https://attic.tinyland.dev)

2. Generate a token with push access:
   ```bash
   # On a machine with Attic configured
   attic login tinyland https://attic.tinyland.dev

   # The token is stored in ~/.config/attic/config.toml
   cat ~/.config/attic/config.toml
   ```

3. Add the token to GitHub:
   - Go to Repository Settings > Secrets and variables > Actions
   - Click "New repository secret"
   - Name: `ATTIC_TOKEN`
   - Value: Your Attic token

### Token Permissions

The token should have:
- `push` access to the `tinyland` cache
- Read access for substituter configuration

## Workflow Behavior

### Cache Strategy

1. **Pull (substituter)**: Before building, the workflow configures Attic as a Nix substituter, allowing cached builds to be downloaded instead of rebuilt.

2. **Push**: After successful builds, results are pushed to the cache for future use.

### When Cache is Used

- `push` to `main` or `develop`: Builds AND pushes to cache
- `pull_request`: Builds only (pulls from cache, but doesn't push)
- `workflow_dispatch`: Configurable via input parameter

### Build Matrix

| Platform | Architecture | Runner | Notes |
|----------|--------------|--------|-------|
| Linux | x86_64 | ubuntu-latest | Native build |
| Linux | aarch64 | ubuntu-latest + QEMU | Emulated, slower |
| macOS | x86_64 | macos-13 | Intel Mac |
| macOS | aarch64 | macos-14 | Apple Silicon |

## Flake Structure

The `flake.nix` provides:

```nix
packages = {
  remote-juggler      # Chapel CLI (WIP - Chapel not yet in Nix)
  remote-juggler-gui  # Rust GTK4 GUI
  default             # Alias for remote-juggler
};

devShells.default     # Development environment with Rust + GTK
```

### Current Limitations

1. **Chapel**: Not available in nixpkgs. The flake includes a placeholder derivation.
   - For production builds, use the existing `ci.yml` workflow
   - Chapel builds are handled via direct binary downloads

2. **GTK GUI on macOS**: GTK4 builds are Linux-only in this configuration.

## Troubleshooting

### "ATTIC_TOKEN not set" Warning

The workflow will continue without caching. To fix:
1. Add the `ATTIC_TOKEN` secret as described above
2. Verify the token has push access

### Flake Check Failures

If `nix flake check` fails:
1. Ensure `flake.nix` syntax is correct
2. Run `nix flake check --show-trace` locally for detailed errors

### aarch64 Build Timeouts

QEMU emulation is slow. Consider:
1. Using GitHub's ARM runners when available
2. Building on native aarch64 hardware via self-hosted runners
3. Cross-compilation (requires additional setup)

### Cache Miss Despite Previous Build

Possible causes:
1. Nix input changed (e.g., nixpkgs updated)
2. Source files changed
3. Attic cache eviction

## Manual Attic Operations

```bash
# Login to Attic
attic login tinyland https://attic.tinyland.dev <token>

# Push a local build result
nix build .#remote-juggler
attic push tinyland result

# Configure as substituter
attic use tinyland

# List cached paths
attic cache info tinyland
```

## Integration with Existing CI

The `nix-ci.yml` workflow runs **alongside** the existing workflows:

- `ci.yml`: Traditional Chapel + Rust builds (continues to work)
- `gtk-gui.yml`: Dedicated GTK GUI workflow (continues to work)
- `release.yml`: Release automation (continues to work)
- `nix-ci.yml`: Nix-based builds with caching (new)

Artifacts from all workflows are available in GitHub Actions, with Nix artifacts prefixed with `remote-juggler-nix-*`.
