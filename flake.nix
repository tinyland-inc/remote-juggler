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

    # Optional: Custom Chapel fork for Nix support development
    # Usage: nix build --override-input chapel-src github:jesssullivan/chapel/sid-nix-support .#remote-juggler
    chapel-src = {
      url = "github:chapel-lang/chapel/refs/tags/2.7.0";
      flake = false;  # Raw source, not a flake
    };
  };

  nixConfig = {
    # Attic binary cache configuration
    extra-substituters = [
      "https://nix-cache.fuzzy-dev.tinyland.dev/tinyland"
    ];
    extra-trusted-public-keys = [
      "tinyland:/o3SR1lItco+g3RLb6vgAivYa6QjmokbnlNSX+s8ric="
    ];
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, chapel-src }:
    {
      # System-independent outputs for consumption by other flakes
      overlays.default = final: prev: {
        remote-juggler = self.packages.${prev.stdenv.hostPlatform.system}.remote-juggler;
        rj-gateway = self.packages.${prev.stdenv.hostPlatform.system}.rj-gateway;
        pinentry-remotejuggler = self.packages.${prev.stdenv.hostPlatform.system}.pinentry-remotejuggler;
      } // (if prev.stdenv.isLinux then {
        remote-juggler-gui = self.packages.${prev.stdenv.hostPlatform.system}.remote-juggler-gui;
      } else {});

      homeManagerModules.default = import ./nix/homeManagerModule.nix;
    }
    //
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

        # Chapel built from source using system LLVM.
        # Works on both Linux and macOS without FHS/bubblewrap.
        chapel = import ./nix/chapel.nix {
          inherit pkgs chapel-src;
        };

        # Legacy: FHS-based Chapel environment for Linux (kept for backward compat)
        chapelFhs = if pkgs.stdenv.isLinux then
          import ./nix/chapel-fhs.nix { inherit pkgs chapelVersion; }
        else
          null;

        # Rust toolchain for GTK GUI
        # Using Rust 1.85+ for edition2024 support (required by cfg-expr crate)
        rustToolchain = pkgs.rust-bin.stable."1.85.0".default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
          targets = [ ];
        };

        # Custom rustPlatform using our Rust 1.85 toolchain
        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
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

        # TPM2-TSS dependencies for HSM library (Linux only)
        tpm2Deps = pkgs.lib.optionals pkgs.stdenv.isLinux [
          pkgs.tpm2-tss
        ];

        # TPM testing tools (devShell only, Linux only)
        tpmTestDeps = pkgs.lib.optionals pkgs.stdenv.isLinux [
          pkgs.swtpm
          pkgs.tpm2-tools
        ];

        # Common build inputs for Chapel projects
        chapelBuildInputs = [
          chapel
          pkgs.gnumake
          pkgs.git
        ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
          pkgs.darwin.apple_sdk.frameworks.Security
          pkgs.darwin.apple_sdk.frameworks.CoreFoundation
        ];

        # Build the Chapel CLI binary using Chapel built from source
        remote-juggler = pkgs.stdenv.mkDerivation {
          pname = "remote-juggler";
          version = "2.1.0";

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

          buildPhase = ''
            export HOME=$(mktemp -d)
            mkdir -p target/release

            # HSM header is needed for Chapel's extern declarations even when
            # HSM_NATIVE_AVAILABLE=false (module is defined but not used at runtime).
            ${chapel}/bin/chpl \
              -M src/remote_juggler \
              --ccflags="-I$src/pinentry" \
              -sHSM_NATIVE_AVAILABLE=false \
              --fast \
              -o target/release/remote_juggler \
              src/remote_juggler.chpl
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp target/release/remote_juggler $out/bin/remote-juggler
            chmod +x $out/bin/remote-juggler
          '';

          meta = with pkgs.lib; {
            description = "Backend-agnostic git identity management with MCP/ACP support";
            homepage = "https://gitlab.com/tinyland/projects/remote-juggler";
            license = licenses.zlib;
            maintainers = [ ];
            platforms = platforms.unix;
          };
        };

        # Build the pinentry HSM helper library (Linux/macOS)
        pinentry-remotejuggler = pkgs.stdenv.mkDerivation {
          pname = "pinentry-remotejuggler";
          version = "1.0.0";

          src = pkgs.lib.cleanSourceWith {
            src = ./pinentry;
            filter = path: type:
              let baseName = baseNameOf (toString path);
              in !(baseName == "test_hsm" ||
                   baseName == "*.o" ||
                   baseName == "*.dylib" ||
                   baseName == "*.so");
          };

          nativeBuildInputs = [
            pkgs.gnumake
            pkgs.pkg-config
          ];

          buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.tpm2-tss
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.darwin.apple_sdk.frameworks.Security
            pkgs.darwin.apple_sdk.frameworks.CoreFoundation
          ];

          buildPhase = ''
            make all
          '';

          installPhase = ''
            mkdir -p $out/lib $out/bin $out/include

            # Install shared library
            if [ -f libhsm_remotejuggler.so ]; then
              cp libhsm_remotejuggler.so $out/lib/
            elif [ -f libhsm_remotejuggler.dylib ]; then
              cp libhsm_remotejuggler.dylib $out/lib/
            fi

            # Install pinentry script
            cp pinentry-remotejuggler.py $out/bin/pinentry-remotejuggler
            chmod +x $out/bin/pinentry-remotejuggler

            # Install header
            cp hsm.h $out/include/
          '';

          meta = with pkgs.lib; {
            description = "HSM-backed pinentry for RemoteJuggler with TPM/SecureEnclave support";
            homepage = "https://gitlab.com/tinyland/projects/remote-juggler";
            license = licenses.zlib;
            platforms = platforms.unix;
          };
        };

        # Build the Rust GTK GUI (Linux only)
        remote-juggler-gui = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux (
          rustPlatform.buildRustPackage {
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
              license = licenses.zlib;
              platforms = platforms.linux;
            };
          }
        );

        # Build the Go gateway (all platforms)
        rj-gateway = pkgs.buildGoModule {
          pname = "rj-gateway";
          version = "2.1.0";

          src = pkgs.lib.cleanSourceWith {
            src = ./gateway;
            filter = path: type:
              let baseName = baseNameOf (toString path);
              in !(baseName == "Dockerfile");
          };

          vendorHash = null; # Set after first build, or use goModules

          # Skip vendor hash check during development
          proxyVendor = true;

          ldflags = [ "-s" "-w" ];

          meta = with pkgs.lib; {
            description = "RemoteJuggler MCP gateway with tsnet, Setec, and additive credential resolution";
            homepage = "https://github.com/tinyland-inc/remote-juggler";
            license = licenses.zlib;
            platforms = platforms.unix;
          };
        };

      in {
        packages = {
          inherit remote-juggler rj-gateway pinentry-remotejuggler chapel;
          default = remote-juggler;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          inherit remote-juggler-gui;
          # Legacy FHS Chapel environment (kept for backward compat)
          chapel-fhs = chapelFhs.chapel-fhs;
        };

        # Development shell with all tools
        devShells.default = pkgs.mkShell {
          name = "remote-juggler-dev";

          buildInputs = [
            # Rust toolchain
            rustToolchain

            # Chapel (built from source with system LLVM)
            chapel

            # GTK4 development (Linux)
          ] ++ gtkDeps ++ [
            # Common tools
            pkgs.git
            pkgs.just
            pkgs.gnumake  # needed by pinentry/Makefile and Chapel internals
            pkgs.pkg-config

            # Rust tools
            pkgs.cargo-watch
            pkgs.cargo-audit

            # CI/CD tools
            pkgs.jq
            pkgs.curl

            # KeePassXC CLI for credential authority
            pkgs.keepassxc

            # Go toolchain for gateway development
            pkgs.go
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.darwin.apple_sdk.frameworks.Security
            pkgs.darwin.apple_sdk.frameworks.CoreFoundation
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            # Xvfb for headless testing
            pkgs.xvfb-run
          ]
          # TPM2-TSS for HSM library builds
          ++ tpm2Deps
          # TPM testing tools
          ++ tpmTestDeps;

          shellHook = ''
            echo "RemoteJuggler Development Environment"
            echo "======================================"
            echo ""
            echo "Chapel version: ${chapelVersion} (built from source with LLVM 18)"
            echo "  Quick test: chpl --version"
            echo ""
            echo "Available commands:"
            echo "  just build        - Build Chapel CLI (debug)"
            echo "  just release      - Build Chapel CLI (release)"
            echo "  just test         - Run Chapel tests"
            ${pkgs.lib.optionalString pkgs.stdenv.isLinux ''
              echo "  cargo build       - Build GTK GUI (in gtk-gui/)"
              echo "  cargo test        - Run GTK GUI tests"
              echo ""
              echo "TPM/HSM development:"
              echo "  just hsm          - Build HSM library"
              echo "  just hsm-test     - Run HSM unit tests"
              echo "  swtpm --version          - Software TPM available"
            ''}
            echo ""
            echo "Attic cache: https://nix-cache.fuzzy-dev.tinyland.dev/tinyland"
            echo ""

            # RemoteJuggler identity auto-switching
            if command -v remote-juggler >/dev/null 2>&1; then
              if [ -d .git ] || git rev-parse --git-dir >/dev/null 2>&1; then
                DETECTED=$(remote-juggler detect --quiet 2>/dev/null)
                if [ -n "$DETECTED" ]; then
                  echo "RemoteJuggler: Detected identity '$DETECTED'"
                fi
              fi
            fi
          '';

          # Ensure pkg-config can find GTK
          PKG_CONFIG_PATH = pkgs.lib.optionalString pkgs.stdenv.isLinux
            (pkgs.lib.makeSearchPath "lib/pkgconfig" gtkDeps);
        };

        # Chapel-only development shell (all platforms)
        devShells.chapel = pkgs.mkShell {
          name = "remote-juggler-chapel";
          buildInputs = chapelBuildInputs;

          shellHook = ''
            echo "Chapel Development Shell"
            echo "========================"
            echo "Chapel ${chapelVersion} (from source, LLVM 18)"
            echo "  chpl --version"
          '';
        };

        # TPM development shell (Linux only) for HSM testing
        devShells.tpm = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux (pkgs.mkShell {
          name = "remote-juggler-tpm-dev";

          buildInputs = [
            pkgs.tpm2-tss
            pkgs.swtpm
            pkgs.tpm2-tools
            pkgs.gnumake
            pkgs.gcc
            pkgs.pkg-config
          ];

          shellHook = ''
            echo "TPM Development Shell"
            echo "====================="
            echo ""
            echo "TPM2-TSS: $(pkg-config --modversion tss2-esys 2>/dev/null || echo 'not found')"
            echo "swtpm: $(swtpm --version 2>&1 | head -1)"
            echo ""
            echo "Quick Start - Software TPM:"
            echo "  mkdir -p /tmp/swtpm-test"
            echo "  swtpm socket --tpmstate dir=/tmp/swtpm-test --tpm2 \\"
            echo "    --ctrl type=tcp,port=2322 --server type=tcp,port=2321 &"
            echo "  export TPM2TOOLS_TCTI='swtpm:host=localhost,port=2321'"
            echo "  tpm2_getcap properties-fixed"
            echo ""
            echo "Build pinentry with TPM support:"
            echo "  just hsm && just hsm-test"
          '';
        });

        # For `nix flake check`
        checks = {
          # Test that Chapel from-source build works
          chapel-version = pkgs.runCommand "check-chapel-version" {
            nativeBuildInputs = [ chapel ];
          } ''
            ${chapel}/bin/chpl --version > $out
          '';
        };
      }
    );
}
