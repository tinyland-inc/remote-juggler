# typed: false
# frozen_string_literal: true

# Homebrew formula for RemoteJuggler
# Git identity management tool with MCP/ACP agent protocol support
#
# Installation:
#   brew tap tinyland/tools https://gitlab.com/tinyland/homebrew-tools.git
#   brew install remote-juggler
#
class RemoteJuggler < Formula
  desc "Backend-agnostic git identity management with MCP/ACP agent protocol support"
  homepage "https://github.com/Jesssullivan/RemoteJuggler"
  version "2.1.0-beta.3"
  license "Zlib"

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/Jesssullivan/RemoteJuggler/releases/download/v2.1.0-beta.3/remote-juggler-linux-arm64"
      sha256 "aa16768b161beb9a957b90c595a567bbba05cf2808b7d550f01cc65f08b83459" # Updated by release workflow
    else
      url "https://github.com/Jesssullivan/RemoteJuggler/releases/download/v2.1.0-beta.3/remote-juggler-linux-amd64"
      sha256 "f4ae82cb5eddd582005cdc770f6c45f4a5a13cc71be54178d88a44eacf5bed24" # Updated by release workflow
    end
  end

  def install
    bin.install "remote-juggler"

    # Install shell completions if present
    bash_completion.install "completions/remote-juggler.bash" if File.exist?("completions/remote-juggler.bash")
    zsh_completion.install "completions/_remote-juggler" if File.exist?("completions/_remote-juggler")
    fish_completion.install "completions/remote-juggler.fish" if File.exist?("completions/remote-juggler.fish")

    # Install man page if present
    man1.install "man/remote-juggler.1" if File.exist?("man/remote-juggler.1")
  end

  def caveats
    <<~EOS
      RemoteJuggler has been installed!

      Quick start:
        remote-juggler status          # Show current identity
        remote-juggler list            # List all identities
        remote-juggler switch <name>   # Switch identity

      MCP server mode (for AI agents):
        remote-juggler --mode=mcp

      Configuration:
        ~/.config/remote-juggler/config.json

      Documentation:
        https://transscendsurvival.org/RemoteJuggler/

      macOS users: This formula currently provides Linux binaries only.
      For macOS, install via:
        curl -fsSL https://raw.githubusercontent.com/Jesssullivan/RemoteJuggler/main/install.sh | bash
      Or: npx @tummycrypt/remote-juggler

      For Claude Code integration, add to .mcp.json:
        {
          "mcpServers": {
            "remote-juggler": {
              "command": "#{opt_bin}/remote-juggler",
              "args": ["--mode=mcp"]
            }
          }
        }
    EOS
  end

  test do
    assert_match "RemoteJuggler v#{version}", shell_output("#{bin}/remote-juggler --version")
    assert_match "identity", shell_output("#{bin}/remote-juggler --help")
  end
end
