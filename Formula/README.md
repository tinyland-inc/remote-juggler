# RemoteJuggler Homebrew Formula

## Installation

### From Homebrew Tap (Recommended)

```bash
brew tap tinyland/tools https://github.com/tinyland-inc/homebrew-tap.git
brew install remote-juggler
```

### From Local Formula

```bash
brew install --build-from-source ./Formula/remote-juggler.rb
```

### From GitLab Release

```bash
brew install https://raw.githubusercontent.com/tinyland-inc/remote-juggler/main/Formula/remote-juggler.rb
```

## Post-Installation

### Configure Identities

```bash
# Import from SSH config
remote-juggler config import

# Or add manually
remote-juggler config add personal
```

### Shell Completions

Completions are automatically installed to:
- Bash: `$(brew --prefix)/etc/bash_completion.d/remote-juggler.bash`
- Zsh: `$(brew --prefix)/share/zsh/site-functions/_remote-juggler`
- Fish: `$(brew --prefix)/share/fish/vendor_completions.d/remote-juggler.fish`

To enable in your current shell:
```bash
# Bash
source $(brew --prefix)/etc/bash_completion.d/remote-juggler.bash

# Zsh (add to ~/.zshrc)
fpath=($(brew --prefix)/share/zsh/site-functions $fpath)
autoload -Uz compinit && compinit

# Fish
# Completions auto-load in fish
```

### MCP Integration (Claude Code)

Add to `~/.config/claude/mcp.json`:
```json
{
  "mcpServers": {
    "remote-juggler": {
      "command": "remote-juggler",
      "args": ["--mode=mcp"]
    }
  }
}
```

## Updating

```bash
brew update
brew upgrade remote-juggler
```

## Uninstalling

```bash
brew uninstall remote-juggler
brew untap tinyland/tools
```

## Development

### Testing Formula Locally

```bash
brew install --build-from-source --verbose --debug ./Formula/remote-juggler.rb
```

### Audit Formula

```bash
brew audit --strict --online ./Formula/remote-juggler.rb
```

## Creating a Homebrew Tap

The official tap repository is at `tinyland/homebrew-tools`:

```bash
# Clone the tap repo
git clone git@gitlab.com:tinyland/homebrew-tools.git
cd homebrew-tools

# Copy the formula
cp ../remote-juggler/Formula/remote-juggler.rb Formula/

# Commit and push
git add Formula/remote-juggler.rb
git commit -m "feat: update RemoteJuggler formula"
git push
```

Then users can install with:
```bash
brew tap tinyland/tools https://github.com/tinyland-inc/homebrew-tap.git
brew install remote-juggler
```

## Bottle (Binary Package)

For faster installation, create bottles:

```bash
# Build bottle for current platform
brew install --build-bottle ./Formula/remote-juggler.rb
brew bottle --json --root-url=https://github.com/tinyland-inc/remote-juggler/releases/download remote-juggler

# Upload .tar.gz to GitLab release
# Update formula with bottle SHA256
```
