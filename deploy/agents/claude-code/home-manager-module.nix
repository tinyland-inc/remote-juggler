# RemoteJuggler Gateway integration for crush-dots lab machines.
#
# This module is designed to be imported into crush-dots:
#   nix/home-manager/remote-juggler-gateway.nix
#
# It provides:
#   - Greedy secret ingestion (crawl env + KDBX on login)
#   - SOPS/KDBX parity in the agent console
#   - Aperture integration via tsnet
#   - Fuzzy finding of secrets directly from Claude Code
#
# Usage in crush-dots nix/hosts/base.nix:
#   programs.remote-juggler = {
#     enable = true;
#     gateway.enable = true;
#     gateway.setecUrl = "https://setec.tail1234.ts.net";
#     gateway.setecSecrets = [
#       "neon-database-url"
#       "github-token"
#       "gitlab-token"
#       "attic-token"
#     ];
#   };
#
# To add to crush-dots:
#   1. Copy this file to nix/home-manager/remote-juggler-gateway.nix
#   2. Add to nix/home-manager/default.nix imports
#   3. Add feature flag in nix/hosts/base.nix
#   4. Enable in relevant host profiles
#
{ config, lib, pkgs, ... }:

let
  cfg = config.tinyland.remote-juggler;
  rjFlake = builtins.getFlake "github:tinyland-inc/remote-juggler";
  rjPkgs = rjFlake.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.tinyland.remote-juggler = {
    enable = lib.mkEnableOption "RemoteJuggler with gateway on lab machines";

    setecUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Setec server URL (e.g. https://setec.tail1234.ts.net)";
    };

    greedyIngestion = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-crawl env vars and .env files for secret ingestion on login.";
    };

    secrets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "neon-database-url"
        "github-token"
        "gitlab-token"
        "attic-token"
      ];
      description = "Secret names to pre-fetch from Setec.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable RemoteJuggler with gateway
    programs.remote-juggler = {
      enable = true;
      package = rjPkgs.remote-juggler;
      gateway = {
        enable = true;
        package = rjPkgs.rj-gateway;
        localMode = true;
        setecUrl = cfg.setecUrl;
        setecSecrets = cfg.secrets;
      };
      mcp.clients = [ "claude-code" ];
    };

    # Greedy ingestion on login: crawl env vars and discover secrets
    home.activation.rjGreedyIngest = lib.mkIf cfg.greedyIngestion (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if command -v remote-juggler >/dev/null 2>&1; then
          # Initialize KDBX if not exists
          $DRY_RUN_CMD remote-juggler keys init --quiet 2>/dev/null || true
          # Crawl environment variables for secrets
          $DRY_RUN_CMD remote-juggler keys crawl --quiet 2>/dev/null || true
          # Discover .env files in common locations
          $DRY_RUN_CMD remote-juggler keys discover --quiet 2>/dev/null || true
        fi
      ''
    );

    # Claude Code project-level CLAUDE.md snippet for gateway awareness
    home.file.".claude/projects-shared/tinyland/CLAUDE.md".text = lib.mkAfter ''

      ## RemoteJuggler Gateway (Lab Integration)

      This machine has rj-gateway configured for composite credential resolution.
      Available MCP tools:
      - `juggler_resolve_composite` - Resolve secrets from env/SOPS/KDBX/Setec
      - `juggler_setec_list` - List secrets in Tailscale Setec
      - `juggler_setec_get` - Get a secret from Setec
      - `juggler_audit_log` - View credential access audit trail
      - All 36 standard RemoteJuggler MCP tools

      ### Quick credential lookup:
      Use `juggler_resolve_composite` with query matching the secret name.
      Sources are checked in order: env > SOPS > KDBX > Setec.
    '';
  };
}
