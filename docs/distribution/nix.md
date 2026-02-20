# Nix Installation & Development

RemoteJuggler supports Nix for reproducible builds and development environments.

## Quick Start

### Using the DevShell

```bash
# Enter development environment
nix develop

# Build debug version
just build

# Build release version
just release
```

### Building with Nix

```bash
# Build the Chapel CLI (Linux)
nix build .#remote-juggler

# Build the GTK GUI (Linux only)
nix build .#remote-juggler-gui

# Build Chapel compiler package (Linux)
nix build .#chapel
```

## Binary Cache (Attic)

RemoteJuggler uses an Attic binary cache to avoid rebuilding Chapel and other large dependencies.

### Cache Configuration

The flake.nix includes cache configuration that works automatically:

```nix
nixConfig = {
  extra-substituters = [
    "https://attic.tinyland.dev/tinyland"
  ];
  extra-trusted-public-keys = [
    "tinyland:O1ECUdLTRVhoyLTQ3hYy6xFhFyhlcVqbILJxBVOTwRY="
  ];
};
```

### Manual Cache Configuration

If you need to configure the cache manually, add to `~/.config/nix/nix.conf`:

```ini
extra-substituters = https://attic.tinyland.dev/tinyland
extra-trusted-public-keys = tinyland:O1ECUdLTRVhoyLTQ3hYy6xFhFyhlcVqbILJxBVOTwRY=
```

## Platform Support

| Platform | Chapel CLI | GTK GUI | DevShell |
|----------|-----------|---------|----------|
| Linux x86_64 | Full Nix build | Full Nix build | Full |
| Linux aarch64 | Full Nix build | Full Nix build | Full |
| macOS x86_64 | Homebrew required | N/A | Partial |
| macOS aarch64 | Homebrew required | N/A | Partial |

### macOS Notes

Chapel does not provide pre-built macOS binaries. On macOS, the Nix flake provides:

1. **DevShell**: Rust toolchain and common tools
2. **Chapel shim**: Wraps system Chapel (install via Homebrew)

To use on macOS:

```bash
# Install Chapel via Homebrew
brew install chapel

# Enter devShell (uses Homebrew Chapel)
nix develop

# Build with just (not nix build)
just release
```

## CI/CD Integration

### GitLab CI with Nix

Include the Nix CI configuration in your `.gitlab-ci.yml`:

```yaml
include:
  - local: 'ci/gitlab-nix.yml'
```

Or use specific jobs:

```yaml
# Build with Nix
build:nix:
  image: nixos/nix:2.28.3
  script:
    - echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf
    - echo 'extra-substituters = https://attic.tinyland.dev/tinyland' >> /etc/nix/nix.conf
    - echo 'extra-trusted-public-keys = tinyland:O1ECUdLTRVhoyLTQ3hYy6xFhFyhlcVqbILJxBVOTwRY=' >> /etc/nix/nix.conf
    - nix build .#remote-juggler
```

### Environment Variables

For CI cache push access:

| Variable | Description |
|----------|-------------|
| `ATTIC_TOKEN` | Authentication token for Attic cache push |
| `ATTIC_SERVER` | Attic server URL (default: `https://attic.tinyland.dev`) |
| `ATTIC_CACHE` | Cache name (default: `tinyland`) |

## Available Packages

| Package | Description |
|---------|-------------|
| `remote-juggler` | Chapel CLI binary (default) |
| `remote-juggler-gui` | GTK4/Libadwaita GUI (Linux only) |
| `chapel` | Chapel compiler 2.7.0 (Linux only) |

## Available DevShells

| Shell | Description |
|-------|-------------|
| `default` | Full development environment (Rust + Chapel + GTK) |
| `chapel` | Minimal Chapel-only environment |

```bash
# Full devShell
nix develop

# Chapel-only shell
nix develop .#chapel
```

## Troubleshooting

### Chapel binary not found

On Linux, verify Chapel is in the Nix store:

```bash
nix build .#chapel
./result/bin/chpl --version
```

### Cache not being used

1. Check cache is configured:
   ```bash
   nix show-config | grep substituters
   ```

2. Verify key is trusted:
   ```bash
   nix show-config | grep trusted-public-keys
   ```

3. Test cache connectivity:
   ```bash
   curl -I https://attic.tinyland.dev/tinyland
   ```

### GTK GUI build fails

Ensure GTK4 development libraries are available:

```bash
# Nix should handle this, but verify:
nix develop --command pkg-config --modversion gtk4
```

### macOS build issues

Remember: Nix builds on macOS require Homebrew Chapel:

```bash
# Install Chapel
brew install chapel

# Verify installation
which chpl
chpl --version

# Then use just (not nix build)
just release
```

## Development Workflow

### Recommended Workflow (Linux)

```bash
# Enter devShell
nix develop

# Development cycle
just build        # Quick debug build
just test         # Run tests
just lint         # Run linter

# Release build
nix build         # Full reproducible build
```

### Recommended Workflow (macOS)

```bash
# Ensure Homebrew Chapel is installed
brew install chapel

# Enter devShell for Rust tooling
nix develop

# Build with just
just release
```

## Updating Chapel Version

To update Chapel in the flake:

1. Update `chapelVersion` in `flake.nix`
2. Update SHA256 hashes:
   ```bash
   nix-prefetch-url https://github.com/chapel-lang/chapel/releases/download/X.Y.Z/chapel-X.Y.Z-1.ubuntu24.amd64.deb
   nix-prefetch-url https://github.com/chapel-lang/chapel/releases/download/X.Y.Z/chapel-X.Y.Z-1.ubuntu24.arm64.deb
   ```
3. Update flake.lock:
   ```bash
   nix flake update
   ```
