---
title: "Building from Source"
description: "Build RemoteJuggler from Chapel source code. Covers compiler requirements, justfile targets, and cross-compilation."
category: "reference"
llm_priority: 5
keywords:
  - build
  - chapel
  - compiler
  - justfile
  - source
---

# Building from Source

Build RemoteJuggler from source code.

## Requirements

### Chapel Compiler

Install Chapel 2.7.0 or later:

**Nix (recommended):**
```bash
nix develop  # Provides Chapel 2.7.0 + all build tools
```

**Linux (Spack):**
```bash
spack install chapel
```

**From Source:**
```bash
git clone https://github.com/chapel-lang/chapel.git
cd chapel
./configure
make
source util/quickstart/setchplenv.bash
```

### Build Tools

- Just
- C compiler (for FFI code)

## Build Commands

### Debug Build

```bash
just build
```

Output: `target/debug/remote-juggler`

Features:
- Full debugging symbols
- Assertions enabled
- No optimizations

### Release Build

```bash
just release
```

Output: `target/release/remote-juggler`

Features:
- Optimizations enabled (`--fast`)
- Smaller binary
- Production ready

### Clean

```bash
just clean
```

Removes build artifacts.

## Justfile Reference

Key recipes from `justfile`:

```just
# Recipes
build       # Debug build
release     # Optimized build
test        # Run tests
lint        # Check code style
install     # Install to $HOME/.local/bin
clean       # Remove artifacts
```

## Mason Build

Alternative build using Chapel's package manager:

```bash
# Initialize (if needed)
mason update

# Debug build
mason build

# Release build
mason build --release
```

Note: Mason may not properly pass linker flags for macOS frameworks. Use `just` for production builds.

## Cross-Compilation

### Linux on macOS

Not directly supported. Use CI/CD for Linux builds.

### Building in Docker

```dockerfile
FROM chapel/chapel:2.7

WORKDIR /app
COPY . .
RUN just release
```

## Build Troubleshooting

### "Module not found"

Ensure `-M src/remote_juggler` is in compiler flags:

```bash
chpl -M src/remote_juggler src/remote_juggler.chpl
```

### "Undefined symbols" (macOS)

Add framework linker flags:

```bash
chpl --ldflags="-framework Security -framework CoreFoundation" ...
```

### "chpl: command not found"

Chapel not in PATH:

```bash
# Homebrew
eval "$(brew --prefix chapel)/util/quickstart/setchplenv.bash"

# Source install
source $CHPL_HOME/util/quickstart/setchplenv.bash
```

## Build Configuration

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `CHPL_HOME` | Chapel installation directory |
| `CHPL_TARGET_PLATFORM` | Target platform (darwin, linux) |
| `CHPL_LLVM` | Use LLVM backend (system, bundled) |

### Compiler Flags

| Flag | Purpose |
|------|---------|
| `-M <dir>` | Module search path |
| `--fast` | Enable optimizations |
| `-o <file>` | Output file name |
| `--ldflags` | Linker flags |
| `--main-module` | Specify main module |

## Binary Size

Typical sizes:

| Build | Size |
|-------|------|
| Debug | ~15 MB |
| Release | ~5 MB |
| Release + strip | ~3 MB |

Strip debug symbols:

```bash
strip target/release/remote-juggler
```
