# Nix Installation & Development

RemoteJuggler supports Nix for reproducible builds and development environments. Chapel is consumed from the [Jesssullivan/chapel](https://github.com/Jesssullivan/chapel/tree/llvm-21-support) Nix fork with system LLVM 19 (`inputs.nixpkgs.follows` ensures ABI alignment). No FHS wrappers or Homebrew required on any platform.

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
# Build the Chapel CLI
nix build .#remote-juggler

# Build the Go gateway
nix build .#rj-gateway

# Build the GTK GUI (Linux only)
nix build .#remote-juggler-gui

# Build the HSM pinentry helper
nix build .#pinentry-remotejuggler

# Build Chapel compiler package
nix build .#chapel
```

## Binary Cache (Attic)

RemoteJuggler uses an Attic binary cache to avoid rebuilding Chapel and other large dependencies.

### Cache Configuration

The flake.nix includes cache configuration that works automatically:

```nix
nixConfig = {
  extra-substituters = [
    "https://nix-cache.fuzzy-dev.tinyland.dev/tinyland"
    "https://nix-cache.fuzzy-dev.tinyland.dev/main"
  ];
  extra-trusted-public-keys = [
    "tinyland:/o3SR1lItco+g3RLb6vgAivYa6QjmokbnlNSX+s8ric="
    "main:PBDvqG8OP3W2XF4QzuqWwZD/RhLRsE7ONxwM09kqTtw="
  ];
};
```

### Manual Cache Configuration

If you need to configure the cache manually, add to `~/.config/nix/nix.conf`:

```ini
extra-substituters = https://nix-cache.fuzzy-dev.tinyland.dev/tinyland https://nix-cache.fuzzy-dev.tinyland.dev/main
extra-trusted-public-keys = tinyland:/o3SR1lItco+g3RLb6vgAivYa6QjmokbnlNSX+s8ric= main:PBDvqG8OP3W2XF4QzuqWwZD/RhLRsE7ONxwM09kqTtw=
```

## Platform Support

| Platform | Chapel CLI | GTK GUI | Gateway | DevShell |
|----------|-----------|---------|---------|----------|
| Linux x86_64 | Full Nix build | Full Nix build | Full Nix build | Full |
| Linux aarch64 | Full Nix build | Full Nix build | Full Nix build | Full |
| macOS x86_64 | Full Nix build | N/A | Full Nix build | Full |
| macOS aarch64 | Full Nix build | N/A | Full Nix build | Full |

All platforms use Chapel from the [Jesssullivan/chapel](https://github.com/Jesssullivan/chapel/tree/llvm-21-support) Nix fork (system LLVM 19, Attic-cached). No Homebrew or external Chapel installation required.

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
    - echo 'extra-substituters = https://nix-cache.fuzzy-dev.tinyland.dev/tinyland' >> /etc/nix/nix.conf
    - echo 'extra-trusted-public-keys = tinyland:/o3SR1lItco+g3RLb6vgAivYa6QjmokbnlNSX+s8ric=' >> /etc/nix/nix.conf
    - nix build .#remote-juggler
```

### Environment Variables

For CI cache push access:

| Variable | Description |
|----------|-------------|
| `ATTIC_TOKEN` | Authentication token for Attic cache push |
| `ATTIC_SERVER` | Attic server URL (default: `https://nix-cache.fuzzy-dev.tinyland.dev`) |
| `ATTIC_CACHE` | Cache name (default: `tinyland`) |

## Available Packages

| Package | Description | Platforms |
|---------|-------------|-----------|
| `remote-juggler` | Chapel CLI binary (default) | All |
| `remote-juggler-gui` | GTK4/Libadwaita GUI | Linux only |
| `rj-gateway` | Go MCP gateway (tsnet + Setec) | All |
| `pinentry-remotejuggler` | HSM pinentry helper | All |
| `chapel` | Chapel compiler (from fork, system LLVM 19) | All |

## Available DevShells

| Shell | Description |
|-------|-------------|
| `default` | Full development environment (Rust + Chapel + Go + GTK) |
| `chapel` | Minimal Chapel-only environment |
| `tpm` | TPM/HSM development tools (Linux only) |

```bash
# Full devShell
nix develop

# Chapel-only shell
nix develop .#chapel

# TPM development (Linux)
nix develop .#tpm
```

## Troubleshooting

### Chapel binary not found

Verify Chapel is in the Nix store:

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
   curl -I https://nix-cache.fuzzy-dev.tinyland.dev/tinyland
   ```

### GTK GUI build fails

Ensure GTK4 development libraries are available:

```bash
# Nix should handle this, but verify:
nix develop --command pkg-config --modversion gtk4
```

## Development Workflow

### Recommended Workflow

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

## Updating Chapel Version

To update Chapel in the flake, override the `chapel-nix` input:

```bash
# Use a different branch of the Chapel Nix fork
nix build --override-input chapel-nix github:Jesssullivan/chapel/other-branch .#remote-juggler

# Use a different Chapel fork entirely
nix build --override-input chapel-nix github:youruser/chapel/your-branch .#remote-juggler
```

Then update `flake.lock` to pin the new version:

```bash
nix flake update chapel-nix
```

For technical details on the from-source Chapel build, see [Nix Chapel Setup](../NIX_CHAPEL_SETUP.md).
