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

        # Import FHS-based Chapel environment for Linux
        # This solves the LLVM symbol compatibility issue by sandboxing Chapel
        # in an FHS environment where Ubuntu binaries work correctly.
        chapelFhs = if pkgs.stdenv.isLinux then
          import ./nix/chapel-fhs.nix { inherit pkgs chapelVersion; }
        else
          null;

        # Chapel environment selection via CHAPEL_VARIANT env var:
        #   - "fhs" (default on Linux): Use FHS sandbox for Ubuntu binary compatibility
        #   - "system": Use system Chapel (Homebrew on macOS, or user-installed)
        #   - "legacy": Use autoPatchelf approach (may have LLVM issues)
        #
        # The FHS approach is recommended for Linux as it avoids the LLVM M68k
        # symbol issue that affects the autoPatchelf approach.

        # Legacy Chapel derivation (autoPatchelf - may have LLVM issues)
        # Kept for reference and fallback, but FHS is preferred
        chapel-legacy = if pkgs.stdenv.isLinux then
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

            # Runtime dependencies Chapel binaries need
            buildInputs = with pkgs; [
              glibc
              gcc.cc.lib
              zlib
              llvmPackages_18.llvm
              llvmPackages_18.libclang
              gmp
              hwloc
              libunwind
              python3
              ncurses
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
              description = "Chapel programming language compiler (legacy autoPatchelf)";
              homepage = "https://chapel-lang.org/";
              license = licenses.asl20;
              platforms = platforms.linux;
            };
          }
        else
          null;

        # System Chapel shim for macOS (uses Homebrew)
        chapel-system = pkgs.writeShellScriptBin "chpl" ''
          if command -v /opt/homebrew/bin/chpl &>/dev/null; then
            exec /opt/homebrew/bin/chpl "$@"
          elif command -v /usr/local/bin/chpl &>/dev/null; then
            exec /usr/local/bin/chpl "$@"
          else
            echo "Error: Chapel not found. Install via: brew install chapel" >&2
            exit 1
          fi
        '';

        # Select Chapel based on platform
        # Linux: Use FHS environment (avoids LLVM compatibility issues)
        # macOS: Use system Chapel (Homebrew)
        chapel = if pkgs.stdenv.isLinux then
          # For Nix builds, we use the extracted Chapel with FHS wrapper
          # The actual chpl binary is accessed through the FHS environment
          chapelFhs.chapel-fhs
        else
          chapel-system;

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

        # Architecture string for Chapel binaries
        chapelArch = if pkgs.stdenv.isAarch64 then "linux64-aarch64" else "linux64-x86_64";

        # Common build inputs for Chapel projects
        chapelBuildInputs = [
          chapel
          pkgs.gnumake
          pkgs.git
        ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
          pkgs.darwin.apple_sdk.frameworks.Security
          pkgs.darwin.apple_sdk.frameworks.CoreFoundation
        ];

        # Build the Chapel CLI binary using FHS environment
        # This avoids LLVM symbol compatibility issues by running Chapel
        # inside an FHS-compatible sandbox
        remote-juggler = pkgs.stdenv.mkDerivation {
          pname = "remote-juggler";
          version = "2.1.0-beta.7";

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

            # Build with chpl inside FHS environment
            # The FHS wrapper provides Ubuntu-like compatibility for Chapel binaries
            # The profile in chapel-fhs.nix sets up CHPL_HOME, PATH, and CHPL_* env vars
            ${chapel}/bin/chapel-fhs -c "
              chpl \
                -M src/remote_juggler \
                --fast \
                -o target/release/remote_juggler \
                src/remote_juggler.chpl
            "
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
            echo "Install: brew install chapel && just release"
            exit 1
            EOF
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

      in {
        packages = {
          inherit remote-juggler pinentry-remotejuggler;
          default = remote-juggler;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          inherit remote-juggler-gui;
          # Chapel FHS environment for Linux
          chapel = chapel;
          chapel-fhs = chapelFhs.chapel-fhs;
          chapel-legacy = chapel-legacy;
        };

        # Development shell with all tools (uses FHS Chapel on Linux)
        devShells.default = pkgs.mkShell {
          name = "remote-juggler-dev";

          buildInputs = [
            # Rust toolchain
            rustToolchain

            # Chapel FHS environment (on Linux) or shim (on macOS)
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
            echo "Chapel version: ${chapelVersion}"
            ${if pkgs.stdenv.isLinux then ''
              echo "Chapel: FHS environment (avoids LLVM compatibility issues)"
              echo "  Enter with: chapel-fhs"
              echo "  Quick test: chapel-fhs -c 'chpl --version'"
              echo ""
              echo "Build with Chapel:"
              echo "  chapel-fhs -c 'just release'"
            '' else ''
              echo "Chapel: Using system Chapel (install via: brew install chapel)"
            ''}
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

        # Chapel FHS shell for minimal Chapel-only builds (Linux)
        # This drops you directly into the FHS environment with Chapel
        devShells.chapel = if pkgs.stdenv.isLinux then
          chapelFhs.devShell
        else
          pkgs.mkShell {
            name = "remote-juggler-chapel";
            buildInputs = chapelBuildInputs;

            shellHook = ''
              echo "Chapel Development Shell (macOS)"
              echo "================================"
              echo "Chapel: Using system Chapel (install via: brew install chapel)"
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
        checks = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          # Test that Chapel FHS environment works
          chapel-fhs-version = pkgs.runCommand "check-chapel-fhs-version" {
            nativeBuildInputs = [ chapel ];
          } ''
            # Test that FHS environment can execute Chapel
            ${chapel}/bin/chapel-fhs -c 'chpl --version' > $out
          '';
        };
      }
    );
}
