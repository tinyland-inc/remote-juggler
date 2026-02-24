# DEPRECATED: Chapel is now consumed from the Jesssullivan/chapel fork flake
# (github:Jesssullivan/chapel/llvm-21-support) which provides parameterized
# Chapel builds with system LLVM. This file is kept as reference/fallback.
#
# ---
# Chapel 2.7.0 from-source Nix derivation (LLVM 18)
#
# Builds Chapel from source using system LLVM, eliminating the need for
# FHS/bubblewrap sandboxing. Works on both Linux and macOS.
#
# The key insight (from twesterhout/nix-chapel): use CHPL_LLVM=system with
# Nix's LLVM and patch the M68k macro detection that fails because Nix's
# LLVM doesn't include exotic backends.
#
# Usage:
#   nix build .#chapel          # Build Chapel compiler
#   nix build .#remote-juggler  # Build RemoteJuggler (uses this Chapel)
#
{ pkgs
, chapel-src
, llvmPackages ? pkgs.llvmPackages_18
}:

let
  lib = pkgs.lib;
  stdenv = llvmPackages.stdenv;

  # Platform prefix for Chapel binary paths
  chplPrefix =
    (if stdenv.isLinux then "linux64-" else "darwin-")
    + (if stdenv.isx86_64 then "x86_64" else "arm64");

  # Chapel environment settings
  chplSettings = {
    CHPL_LLVM = "system";
    CHPL_LLVM_SUPPORT = "system";
    CHPL_LLVM_CONFIG = "${llvmPackages.llvm.dev}/bin/llvm-config";
    CHPL_HOST_COMPILER = "llvm";
    CHPL_HOST_CC = "${llvmPackages.clang}/bin/clang";
    CHPL_HOST_CXX = "${llvmPackages.clang}/bin/clang++";
    CHPL_TARGET_CC = "${llvmPackages.clang}/bin/clang";
    CHPL_TARGET_CXX = "${llvmPackages.clang}/bin/clang++";
    CC = "${llvmPackages.clang}/bin/cc";
    CXX = "${llvmPackages.clang}/bin/c++";
    # Use bundled re2/gmp to avoid version-matching complexity
    CHPL_RE2 = "bundled";
    CHPL_GMP = "bundled";
    CHPL_UNWIND = "none";
    CHPL_LAUNCHER = "none";
    CHPL_TARGET_MEM = "jemalloc";
    CHPL_TARGET_CPU = "none";
  };

  chplBuildEnv = lib.concatStringsSep " "
    (lib.mapAttrsToList (k: v: "${k}='${v}'") chplSettings);

  # Wrapper args for the installed chpl binary
  wrapperArgs = lib.concatStringsSep " " ([
    "--prefix PATH : '${lib.makeBinPath [ pkgs.coreutils pkgs.gnumake pkgs.pkg-config pkgs.python3 pkgs.which ]}'"
    "--set-default CHPL_HOME $out"
  ]
  ++ (lib.mapAttrsToList (k: v: "--set-default ${k} '${v}'") chplSettings));

  # Compiler-specific flags for the chpl wrapper
  compilerWrapperArgs = lib.concatStringsSep " " ([
    "--add-flags '-L ${pkgs.xz.out}/lib'"
  ]
  ++ lib.optionals stdenv.isLinux [
    "--add-flags '-I ${llvmPackages.clang-unwrapped.lib}/lib/clang/${llvmPackages.clang.version}/include'"
    "--add-flags '-I ${llvmPackages.clang}/resource-root/include'"
    "--add-flags '-I ${llvmPackages.bintools.libc.dev}/include'"
  ]
  ++ lib.optionals stdenv.isDarwin [
    "--add-flags '-I ${llvmPackages.clang}/resource-root/include'"
    "--add-flags '-I ${stdenv.libc}/include'"
  ]);

in
stdenv.mkDerivation {
  pname = "chapel";
  version = "2.7.0";
  src = chapel-src;

  postPatch = ''
    patchShebangs --build configure
    patchShebangs --build util/printchplenv
    patchShebangs --build util/config/compileline
    patchShebangs --build util/test/checkChplInstall

    # Disable Python venv builds (we provide deps via Nix)
    export CHPL_DONT_BUILD_CHPLDOC_VENV=1
    export CHPL_DONT_BUILD_TEST_VENV=1
    export CHPL_DONT_BUILD_C2CHAPEL_VENV=1

    # Fix the c2chapel venv Makefile target
    substituteInPlace third-party/Makefile \
      --replace-fail 'cd chpl-venv && $(MAKE) c2chapel-venv' \
                     'if [ -z "$$CHPL_DONT_BUILD_C2CHAPEL_VENV" ]; then cd chpl-venv && $(MAKE) c2chapel-venv; fi'

    # Disable M68k LLVM macro detection.
    # Nix's LLVM doesn't include exotic backends (M68k, AArch64BE, etc.)
    # which causes Chapel's validation to fail. This is the same patch
    # used by twesterhout/nix-chapel.
    substituteInPlace util/chplenv/chpl_llvm.py \
      --replace-warn 'if macro in out' 'if False'
  '';

  configurePhase = ''
    export ${chplBuildEnv}
    # Chapel builds in-place: CHPL_HOME == source directory during build.
    # We configure with --chpl-home pointing at the source dir, then
    # copy results to $out in installPhase.
    ./configure --chpl-home=$(pwd)
  '';

  buildPhase = ''
    make -j$NIX_BUILD_CORES
  '';

  enableParallelBuilding = true;

  installPhase = ''
    # Chapel builds in-place. Copy the needed artifacts to $out.
    mkdir -p $out

    # Core directories needed at runtime
    cp -r bin $out/bin
    cp -r lib $out/lib
    cp -r util $out/util
    cp -r runtime $out/runtime
    cp -r modules $out/modules
    cp -r make $out/make

    # Create module search directories expected by chpl at compile time.
    # These don't exist in the Chapel source tree (only tasktable/ and
    # comm/{gasnet,ofi,ugni} exist). On macOS, LLVM's directory_iterator
    # returns an error code that Chapel's frontend doesn't filter, causing
    # a fatal "No such file or directory in directory traversal" error.
    # Empty directories satisfy the traversal without affecting compilation.
    mkdir -p $out/modules/internal/tasks/qthreads
    mkdir -p $out/modules/internal/tasks/fifo
    mkdir -p $out/modules/internal/comm/none

    # Third-party: only copy install dirs (not build dirs with /build/ refs)
    mkdir -p $out/third-party
    for tp in third-party/*/; do
      tpname=$(basename "$tp")
      # Copy install directories and source configs, skip build dirs and tests
      if [ -d "$tp/install" ]; then
        mkdir -p "$out/third-party/$tpname"
        cp -r "$tp/install" "$out/third-party/$tpname/install"
      fi
      # Copy Makefiles and config needed by Chapel's runtime
      for f in "$tp"Makefile* "$tp"*.cmake "$tp"*.sh; do
        if [ -f "$f" ]; then
          mkdir -p "$out/third-party/$tpname"
          cp "$f" "$out/third-party/$tpname/" || true
        fi
      done
      # Copy source dirs needed at runtime (e.g., qthreads-src, re2-src)
      if [ -d "$tp/''${tpname}-src" ]; then
        mkdir -p "$out/third-party/$tpname"
        cp -r "$tp/''${tpname}-src" "$out/third-party/$tpname/" || true
      fi
    done
    # Copy header-only third-party libraries needed by the runtime
    cp -r third-party/utf8-decoder $out/third-party/

    # Copy top-level third-party Makefile
    cp third-party/Makefile $out/third-party/ || true

    # Config files needed by chpl at runtime
    cp -r configured_prefix $out/configured_prefix || true

    # Ensure scripts are executable
    chmod +x $out/util/printchplenv || true
    chmod +x $out/util/config/compileline || true
    patchShebangs $out/util/
    patchShebangs $out/bin/

    # Wrap printchplenv
    wrapProgram $out/util/printchplenv \
      ${wrapperArgs}
    ln -sf $out/util/printchplenv $out/bin/printchplenv

    # Wrap chpl binary
    makeWrapper $out/bin/${chplPrefix}/chpl $out/bin/chpl \
      ${wrapperArgs} \
      ${compilerWrapperArgs}
  '' + lib.optionalString stdenv.isLinux ''
    # Fix RPATH for shared frontend library on Linux
    if [ -f $out/lib/compiler/${chplPrefix}/libChplFrontendShared.so ]; then
      ${pkgs.patchelf}/bin/patchelf --add-rpath '$ORIGIN' \
        $out/lib/compiler/${chplPrefix}/libChplFrontendShared.so || true
    fi

    # Remove /build/ references from ELF binaries in the output
    find $out -type f -executable | while read f; do
      if file "$f" | grep -q ELF; then
        ${pkgs.removeReferencesTo}/bin/remove-references-to \
          -t /build "$f" 2>/dev/null || true
      fi
    done
    # Also strip references from .so files
    find $out -name '*.so' -o -name '*.so.*' | while read f; do
      ${pkgs.removeReferencesTo}/bin/remove-references-to \
        -t /build "$f" 2>/dev/null || true
    done
  '';

  buildInputs = [
    llvmPackages.llvm
    llvmPackages.libclang.dev
    llvmPackages.clang
  ] ++ lib.optionals stdenv.isLinux [
    pkgs.libunwind
  ];

  nativeBuildInputs = [
    pkgs.bash
    pkgs.cmake
    pkgs.gnumake
    pkgs.gnum4
    pkgs.file
    pkgs.makeWrapper
    pkgs.patchelf
    pkgs.perl
    pkgs.pkg-config
    pkgs.python3
    pkgs.which
    llvmPackages.clang
  ];

  # Don't try to strip Chapel's runtime libraries
  dontStrip = true;

  meta = with lib; {
    description = "Chapel programming language compiler (built from source with system LLVM)";
    homepage = "https://chapel-lang.org/";
    license = licenses.asl20;
    platforms = platforms.unix;
  };
}
