{
  description = "RemoteJuggler - Backend-agnostic git identity management with MCP/ACP support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";

    # Rust toolchain for GTK GUI
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    # Attic binary cache configuration
    extra-substituters = [
      "https://attic.tinyland.dev/tinyland"
    ];
    extra-trusted-public-keys = [
      "tinyland:O1ECUdLTRVhoyLTQ3hYy6xFhFyhlcVqbILJxBVOTwRY="
    ];
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachSystem [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ] (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Chapel version configuration
        chapelVersion = "2.7.0";

        # Chapel binary derivation for Linux (from Ubuntu .deb packages)
        # macOS requires building from source or using Homebrew externally
        chapel = if pkgs.stdenv.isLinux then
          pkgs.stdenv.mkDerivation rec {
            pname = "chapel";
            version = chapelVersion;

            src = if pkgs.stdenv.isAarch64 then
              pkgs.fetchurl {
                url = "https://github.com/chapel-lang/chapel/releases/download/${version}/chapel-${version}-1.ubuntu24.arm64.deb";
                sha256 = "1yc03izg1fgrbx5gyw2z47i542f6s6ia2y2wcbxdjl8bz50lfdpc";
              }
            else
              pkgs.fetchurl {
                url = "https://github.com/chapel-lang/chapel/releases/download/${version}/chapel-${version}-1.ubuntu24.amd64.deb";
                sha256 = "1vvny92jhm98zylpc80xvxx0hrcfi7rlbrnis3fq266gnqs1vq0b";
              };

            nativeBuildInputs = [ pkgs.dpkg pkgs.autoPatchelfHook ];

            # Runtime dependencies Chapel binaries might need
            buildInputs = with pkgs; [
              glibc
              gcc.cc.lib
              zlib
              llvmPackages_16.llvm.lib
              python3
            ];

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              mkdir -p $out
              dpkg-deb -x $src $out

              # Move files from /usr to package root
              if [ -d $out/usr ]; then
                cp -r $out/usr/* $out/ || true
                rm -rf $out/usr
              fi

              # Fix shebangs
              patchShebangs $out/bin || true
            '';

            meta = with pkgs.lib; {
              description = "Chapel programming language compiler";
              homepage = "https://chapel-lang.org/";
              license = licenses.asl20;
              platforms = platforms.linux;
            };
          }
        else
          # For macOS, we provide a shim that uses system Chapel (via Homebrew)
          # This is necessary because Chapel doesn't provide macOS binaries
          pkgs.writeShellScriptBin "chpl" ''
            if command -v /opt/homebrew/bin/chpl &>/dev/null; then
              exec /opt/homebrew/bin/chpl "$@"
            elif command -v /usr/local/bin/chpl &>/dev/null; then
              exec /usr/local/bin/chpl "$@"
            else
              echo "Error: Chapel not found. Install via: brew install chapel" >&2
              exit 1
            fi
          '';

        # Rust toolchain for GTK GUI
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
          targets = [ ];
        };

        # GTK4 dependencies (Linux only)
        gtkDeps = pkgs.lib.optionals pkgs.stdenv.isLinux (with pkgs; [
          gtk4
          libadwaita
          glib
          cairo
          pango
          gdk-pixbuf
          graphene
        ]);

        # Common build inputs for Chapel projects
        chapelBuildInputs = [
          chapel
          pkgs.gnumake
          pkgs.git
        ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
          pkgs.darwin.apple_sdk.frameworks.Security
          pkgs.darwin.apple_sdk.frameworks.CoreFoundation
        ];

        # Build the Chapel CLI binary
        remote-juggler = pkgs.stdenv.mkDerivation {
          pname = "remote-juggler";
          version = "2.0.0";

          src = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              let baseName = baseNameOf (toString path);
              in !(baseName == "target" ||
                   baseName == ".mason" ||
                   baseName == "gtk-gui" ||
                   baseName == "tray" ||
                   baseName == "docs" ||
                   baseName == "site" ||
                   baseName == ".git");
          };

          nativeBuildInputs = chapelBuildInputs ++ [ pkgs.which ];

          # Skip build on macOS unless Chapel is installed via Homebrew
          dontBuild = pkgs.stdenv.isDarwin;

          buildPhase = pkgs.lib.optionalString pkgs.stdenv.isLinux ''
            export HOME=$(mktemp -d)
            mkdir -p target/release

            # Build with chpl directly (Mason has quoting issues)
            ${chapel}/bin/chpl \
              -M src/remote_juggler \
              --fast \
              -o target/release/remote_juggler \
              src/remote_juggler.chpl
          '';

          installPhase = if pkgs.stdenv.isLinux then ''
            mkdir -p $out/bin
            cp target/release/remote_juggler $out/bin/remote-juggler
            chmod +x $out/bin/remote-juggler
          '' else ''
            mkdir -p $out/bin
            cat > $out/bin/remote-juggler << 'EOF'
            #!/bin/sh
            echo "RemoteJuggler: macOS Nix builds require Chapel via Homebrew"
            echo "Install: brew install chapel && make release"
            exit 1
            EOF
            chmod +x $out/bin/remote-juggler
          '';

          meta = with pkgs.lib; {
            description = "Backend-agnostic git identity management with MCP/ACP support";
            homepage = "https://gitlab.com/tinyland/projects/remote-juggler";
            license = licenses.mit;
            maintainers = [ ];
            platforms = platforms.unix;
          };
        };

        # Build the Rust GTK GUI (Linux only)
        remote-juggler-gui = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux (
          pkgs.rustPlatform.buildRustPackage {
            pname = "remote-juggler-gui";
            version = "0.1.0";

            src = ./gtk-gui;

            cargoLock = {
              lockFile = ./gtk-gui/Cargo.lock;
            };

            nativeBuildInputs = [
              pkgs.pkg-config
              pkgs.wrapGAppsHook4
            ];

            buildInputs = gtkDeps;

            # Tests require a display
            doCheck = false;

            meta = with pkgs.lib; {
              description = "GTK4/Libadwaita GUI for RemoteJuggler identity management";
              homepage = "https://gitlab.com/tinyland/projects/remote-juggler";
              license = licenses.mit;
              platforms = platforms.linux;
            };
          }
        );

      in {
        packages = {
          inherit remote-juggler;
          default = remote-juggler;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          inherit remote-juggler-gui;
          chapel = chapel;
        };

        # Development shell with all tools
        devShells.default = pkgs.mkShell {
          name = "remote-juggler-dev";

          buildInputs = [
            # Rust toolchain
            rustToolchain

            # Chapel (on Linux) or shim (on macOS)
            chapel

            # GTK4 development (Linux)
          ] ++ gtkDeps ++ [
            # Common tools
            pkgs.git
            pkgs.gnumake
            pkgs.pkg-config

            # Rust tools
            pkgs.cargo-watch
            pkgs.cargo-audit

            # CI/CD tools
            pkgs.jq
            pkgs.curl
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.darwin.apple_sdk.frameworks.Security
            pkgs.darwin.apple_sdk.frameworks.CoreFoundation
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            # Xvfb for headless testing
            pkgs.xvfb-run
          ];

          shellHook = ''
            echo "RemoteJuggler Development Environment"
            echo "======================================"
            echo ""
            echo "Chapel version: ${chapelVersion}"
            ${if pkgs.stdenv.isLinux then ''
              echo "Chapel binary: ${chapel}/bin/chpl"
            '' else ''
              echo "Chapel: Using system Chapel (install via: brew install chapel)"
            ''}
            echo ""
            echo "Available commands:"
            echo "  make build        - Build Chapel CLI (debug)"
            echo "  make release      - Build Chapel CLI (release)"
            echo "  make test         - Run Chapel tests"
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
              echo "  cargo build       - Build GTK GUI (in gtk-gui/)"
              echo "  cargo test        - Run GTK GUI tests"
            ''}
            echo ""
            echo "Attic cache: https://attic.tinyland.dev/tinyland"
          '';

          # Ensure pkg-config can find GTK
          PKG_CONFIG_PATH = pkgs.lib.optionalString pkgs.stdenv.isLinux
            (pkgs.lib.makeSearchPath "lib/pkgconfig" gtkDeps);
        };

        # Chapel-only shell for minimal builds
        devShells.chapel = pkgs.mkShell {
          name = "remote-juggler-chapel";
          buildInputs = chapelBuildInputs;

          shellHook = ''
            echo "Chapel Development Shell"
            echo "========================"
            ${if pkgs.stdenv.isLinux then ''
              echo "chpl: ${chapel}/bin/chpl"
            '' else ''
              echo "Chapel: Using system Chapel (install via: brew install chapel)"
            ''}
          '';
        };

        # For `nix flake check`
        checks = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          # Test that Chapel is available
          chapel-version = pkgs.runCommand "check-chapel-version" {
            nativeBuildInputs = [ chapel ];
          } ''
            ${chapel}/bin/chpl --version > $out
          '';
        };
      }
    );
}
