# RemoteJuggler GTK4 GUI

A native GNOME application for managing git identities, built with GTK4 and Libadwaita.

## Prerequisites

### Rocky Linux / RHEL / Fedora

```bash
sudo dnf install gtk4-devel libadwaita-devel
```

### Ubuntu / Debian

```bash
sudo apt install libgtk-4-dev libadwaita-1-dev
```

### Arch Linux

```bash
sudo pacman -S gtk4 libadwaita
```

## Building

```bash
# Debug build
cargo build

# Release build (optimized)
cargo build --release
```

## Running

```bash
# Run directly
cargo run

# Or after building
./target/release/remote-juggler-gui
```

## Installation

```bash
# Install binary
sudo install -Dm755 target/release/remote-juggler-gui /usr/local/bin/

# Install desktop file
sudo install -Dm644 data/dev.tinyland.RemoteJuggler.desktop /usr/share/applications/

# Install D-Bus service
sudo install -Dm644 data/dev.tinyland.RemoteJuggler.service /usr/share/dbus-1/services/

# Install AppStream metadata
sudo install -Dm644 data/dev.tinyland.RemoteJuggler.metainfo.xml /usr/share/metainfo/
```

## Architecture

```
gtk-gui/
├── src/
│   ├── main.rs        # Application entry point
│   ├── config.rs      # Config loading (reads remote-juggler config.json)
│   ├── identity.rs    # CLI wrapper for remote-juggler operations
│   └── window.rs      # Main application window (Libadwaita)
├── data/
│   ├── *.desktop      # Desktop entry for GNOME
│   ├── *.service      # D-Bus service for activation
│   └── *.metainfo.xml # AppStream metadata
└── Cargo.toml         # Rust dependencies
```

## Features

- Native GNOME look and feel with Libadwaita
- Identity switching from the GUI
- GPG signing status indicator
- Background service for auto-detection
- Desktop integration (dock icon, notifications)
- D-Bus interface for scripting

## D-Bus Interface

The application exposes a D-Bus interface at `dev.tinyland.RemoteJuggler`:

- `GetCurrentIdentity()` - Returns the active identity
- `SwitchIdentity(name)` - Switch to a different identity
- `ListIdentities()` - List all configured identities
- `GetGPGStatus()` - Check if GPG signing is ready
