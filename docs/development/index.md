# Development

Contributor guide for RemoteJuggler development.

## Prerequisites

- Chapel 2.6.0 or later
- macOS or Linux development environment
- Git
- Make

## Repository Structure

```
remote-juggler/
  src/
    remote_juggler.chpl      # Main entry point
    remote_juggler/          # Submodules
      Core.chpl
      Config.chpl
      Identity.chpl
      ...
  c_src/
    keychain.c               # macOS Keychain FFI
    keychain.h
  test/
    unit/                    # Unit tests
  scripts/
    run-tests.sh             # Test runner
  docs/                      # Documentation
  Makefile                   # Build system
  Mason.toml                 # Chapel package config
```

## Development Workflow

### 1. Clone and Build

```bash
git clone https://gitlab.com/tinyland/projects/remote-juggler.git
cd remote-juggler
make build
```

### 2. Run Tests

```bash
make test
```

### 3. Test Changes

```bash
# Debug build
./target/debug/remote-juggler status

# With verbose output
./target/debug/remote-juggler --verbose list
```

### 4. Build Release

```bash
make release
```

## Code Style

- Use `prototype module` declarations
- 2-space indentation in Chapel
- Descriptive function names
- Document public interfaces with comments

## Testing

See [Testing](testing.md) for running tests.

## Releasing

See [Releasing](releasing.md) for release process.
