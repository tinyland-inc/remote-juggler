# Tinyland Homebrew Tap

Official Homebrew tap for Tinyland tools.

## Installation

```bash
# Add the tap
brew tap tinyland/tools https://gitlab.com/tinyland/homebrew-tools.git

# Install packages
brew install remote-juggler
```

## Available Formulas

| Formula | Description | Version |
|---------|-------------|---------|
| `remote-juggler` | Git identity management with MCP/ACP support | 2.0.0 |

## Updating

```bash
brew update
brew upgrade remote-juggler
```

## Troubleshooting

### Tap not found

If you get an error about the tap not being found, use the full URL:

```bash
brew tap tinyland/tools https://gitlab.com/tinyland/homebrew-tools.git
```

### Permission denied

For private repositories, ensure you have SSH access:

```bash
brew tap tinyland/tools git@gitlab.com:tinyland/homebrew-tools.git
```

### Signature verification

All releases are GPG signed. To verify:

```bash
# Import the signing key
gpg --keyserver keys.openpgp.org --recv-keys B7D382A890EA8DA4

# Download and verify checksums
curl -LO https://gitlab.com/tinyland/projects/remote-juggler/-/releases/v2.0.0/downloads/SHA256SUMS.txt
curl -LO https://gitlab.com/tinyland/projects/remote-juggler/-/releases/v2.0.0/downloads/SHA256SUMS.txt.asc
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt
```

## Source Code

- RemoteJuggler: https://gitlab.com/tinyland/projects/remote-juggler
- This tap: https://gitlab.com/tinyland/homebrew-tools

## License

Formulas in this tap are zlib licensed.
The software they install has its own license (see individual projects).
