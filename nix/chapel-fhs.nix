# DEPRECATED: Use nix/chapel.nix (from-source build) instead.
#
# This FHS environment is kept for backward compatibility but is no longer
# used by default. Chapel is now built from source with system LLVM,
# eliminating the need for FHS sandboxing and bubblewrap.
#
# Original purpose: Chapel 2.7 Ubuntu binaries required an FHS-compatible
# environment because they were built against Ubuntu's LLVM 18 which includes
# all target backends. Nix's LLVM 18 is built with fewer targets.
#
# Usage:
#   nix develop .#chapel-fhs   # Enter FHS-based Chapel environment
#   nix build .#chapel-fhs     # Build the FHS wrapper
#
{ pkgs, chapelVersion ? "2.7.0" }:

let
  # Fetch Chapel .deb package
  chapelDeb = if pkgs.stdenv.isAarch64 then
    pkgs.fetchurl {
      url = "https://github.com/chapel-lang/chapel/releases/download/${chapelVersion}/chapel-${chapelVersion}-1.ubuntu24.arm64.deb";
      sha256 = "1yc03izg1fgrbx5gyw2z47i542f6s6ia2y2wcbxdjl8bz50lfdpc";
    }
  else
    pkgs.fetchurl {
      url = "https://github.com/chapel-lang/chapel/releases/download/${chapelVersion}/chapel-${chapelVersion}-1.ubuntu24.amd64.deb";
      sha256 = "1vvny92jhm98zylpc80xvxx0hrcfi7rlbrnis3fq266gnqs1vq0b";
    };

  # Extract Chapel from the .deb package
  chapelExtracted = pkgs.stdenv.mkDerivation {
    pname = "chapel-extracted";
    version = chapelVersion;
    src = chapelDeb;

    nativeBuildInputs = [ pkgs.dpkg ];

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out
      dpkg-deb -x $src $out

      # Move files from /usr to package root for easier access
      if [ -d $out/usr ]; then
        cp -r $out/usr/* $out/ || true
        rm -rf $out/usr
      fi
    '';
  };

  # Architecture string for Chapel binaries
  chapelArch = if pkgs.stdenv.isAarch64 then "linux64-aarch64" else "linux64-x86_64";

in rec {
  # FHS environment that provides Ubuntu-like compatibility for Chapel
  # This is the recommended approach for Linux Nix users
  chapel-fhs = pkgs.buildFHSEnv {
    name = "chapel-fhs";

    # Target packages available inside the FHS environment
    targetPkgs = pkgs: with pkgs; [
      # Basic C/C++ runtime
      glibc
      gcc.cc.lib
      stdenv.cc.cc.lib
      zlib

      # LLVM 18 - Nix's version works inside FHS sandbox
      llvmPackages_18.llvm
      llvmPackages_18.libclang
      llvmPackages_18.compiler-rt

      # Chapel runtime dependencies
      gmp
      hwloc
      libunwind
      python3
      ncurses
      re2

      # Build tools
      gnumake
      git
      which
      coreutils
      bash
    ];

    # Multi-arch packages (for 32-bit compatibility if needed)
    multiPkgs = pkgs: with pkgs; [
      zlib
    ];

    # Environment setup inside the FHS
    profile = ''
      export CHPL_HOME="${chapelExtracted}"
      export PATH="${chapelExtracted}/bin/${chapelArch}:$PATH"
      export CHPL_LLVM=bundled
      export CHPL_RE2=bundled
      export CHPL_GMP=bundled

      # Make sure Chapel can find its runtime
      export CHPL_RUNTIME_LIB="${chapelExtracted}/lib/chapel/${chapelVersion}/runtime/lib"
      export CHPL_THIRD_PARTY="${chapelExtracted}/lib/chapel/${chapelVersion}/third-party"
    '';

    # Run the default shell
    runScript = "bash";

    # Extra commands to run when building the FHS environment
    extraBuildCommands = ''
      # Ensure Chapel binaries are accessible
      mkdir -p $out/chapel
      ln -sf ${chapelExtracted} $out/chapel/home
    '';
  };

  # A wrapper script that invokes chpl inside the FHS environment
  # This can be used directly without entering the FHS shell
  chpl-fhs = pkgs.writeShellScriptBin "chpl" ''
    exec ${chapel-fhs}/bin/chapel-fhs -c "${chapelExtracted}/bin/${chapelArch}/chpl $*"
  '';

  # Convenience script to enter FHS and run just
  just-fhs = pkgs.writeShellScriptBin "just-fhs" ''
    exec ${chapel-fhs}/bin/chapel-fhs -c "just $*"
  '';

  # Export chapelExtracted for use in builds
  inherit chapelExtracted;

  # DevShell that uses the FHS environment
  devShell = pkgs.mkShell {
    name = "chapel-fhs-dev";

    buildInputs = [
      chapel-fhs
      pkgs.gnumake
      pkgs.git
    ];

    shellHook = ''
      echo "Chapel FHS Development Environment"
      echo "==================================="
      echo ""
      echo "Chapel version: ${chapelVersion}"
      echo "FHS wrapper: ${chapel-fhs}/bin/chapel-fhs"
      echo ""
      echo "Usage:"
      echo "  chapel-fhs              # Enter FHS environment with Chapel"
      echo "  chapel-fhs -c 'chpl x'  # Run chpl directly"
      echo ""
      echo "Quick test:"
      echo "  chapel-fhs -c 'chpl --version'"
      echo ""
    '';
  };
}
