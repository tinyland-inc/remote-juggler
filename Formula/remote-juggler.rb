# RemoteJuggler Homebrew Formula
# To install locally: brew install --build-from-source ./Formula/remote-juggler.rb

class RemoteJuggler < Formula
  desc "Backend-agnostic git identity management with MCP/ACP support"
  homepage "https://gitlab.com/tinyland/projects/remote-juggler"
  url "https://gitlab.com/tinyland/projects/remote-juggler/-/archive/v2.1.0-beta.1/remote-juggler-v2.1.0-beta.1.tar.gz"
  sha256 "" # Will be filled after first release
  license "Zlib"
  head "https://gitlab.com/tinyland/projects/remote-juggler.git", branch: "main"

  depends_on "chapel" => :build
  depends_on "mason" => :build

  def install
    # Build with Mason
    system "mason", "build", "--release"

    # Install binary
    bin.install "target/release/remote_juggler" => "remote-juggler"

    # Install shell completions (if generated)
    if File.exist?("completions/remote-juggler.bash")
      bash_completion.install "completions/remote-juggler.bash"
    end
    if File.exist?("completions/_remote-juggler")
      zsh_completion.install "completions/_remote-juggler"
    end
    if File.exist?("completions/remote-juggler.fish")
      fish_completion.install "completions/remote-juggler.fish"
    end

    # Install man page (if exists)
    if File.exist?("docs/man/remote-juggler.1")
      man1.install "docs/man/remote-juggler.1"
    end
  end

  def post_install
    # Create config directory
    (var/"remote-juggler").mkpath

    # Inform about configuration
    ohai "RemoteJuggler installed!"
    puts <<~EOS

      To get started:
        1. Configure identities: remote-juggler config import
        2. List identities: remote-juggler list
        3. Switch identity: remote-juggler switch <name>

      MCP Server (for Claude Code):
        Add to .mcp.json:
        {
          "mcpServers": {
            "remote-juggler": {
              "command": "remote-juggler",
              "args": ["--mode=mcp"]
            }
          }
        }

      Config location: ~/.config/remote-juggler/config.json
      Documentation: https://tinyland.gitlab.io/projects/remote-juggler
    EOS
  end

  test do
    system "#{bin}/remote-juggler", "--help"
    system "#{bin}/remote-juggler", "--version"
  end
end
