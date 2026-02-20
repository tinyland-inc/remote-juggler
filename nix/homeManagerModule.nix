{ config, lib, pkgs, ... }:

let
  cfg = config.programs.remote-juggler;
  jsonFormat = pkgs.formats.json { };
in
{
  options.programs.remote-juggler = {
    enable = lib.mkEnableOption "RemoteJuggler git identity manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.remote-juggler;
      defaultText = lib.literalExpression "pkgs.remote-juggler";
      description = "The RemoteJuggler CLI package to install.";
    };

    gui = {
      enable = lib.mkEnableOption "RemoteJuggler GTK4 GUI";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.remote-juggler-gui;
        defaultText = lib.literalExpression "pkgs.remote-juggler-gui";
        description = "The RemoteJuggler GUI package to install.";
      };
    };

    mcp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure MCP server entries for AI agent clients.";
      };

      clients = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [
          "claude-code"
          "cursor"
          "vscode"
          "windsurf"
        ]);
        default = [ "claude-code" ];
        description = "Which AI agent clients to configure MCP for.";
      };
    };

    config = lib.mkOption {
      type = lib.types.nullOr jsonFormat.type;
      default = null;
      description = ''
        RemoteJuggler configuration as a Nix attribute set.
        Will be written to ~/.config/remote-juggler/config.json.
        Set to null to manage configuration manually.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ]
      ++ lib.optional (cfg.gui.enable && pkgs.stdenv.isLinux) cfg.gui.package;

    # Write config.json if provided
    xdg.configFile."remote-juggler/config.json" = lib.mkIf (cfg.config != null) {
      source = jsonFormat.generate "remote-juggler-config.json" cfg.config;
    };

    # MCP server configuration for AI agent clients
    xdg.configFile = lib.mkIf cfg.mcp.enable (
      let
        mcpConfig = {
          mcpServers.remote-juggler = {
            command = "${cfg.package}/bin/remote-juggler";
            args = [ "--mode=mcp" ];
          };
        };
        mcpJson = jsonFormat.generate "mcp-config.json" mcpConfig;
      in
      lib.mkMerge [
        # Claude Code
        (lib.mkIf (builtins.elem "claude-code" cfg.mcp.clients) {
          # Claude Code reads from project .mcp.json or ~/.claude/.mcp.json
          # We write a global config that users can reference
          "remote-juggler/mcp-claude.json".source = mcpJson;
        })

        # Cursor
        (lib.mkIf (builtins.elem "cursor" cfg.mcp.clients) {
          # Cursor reads ~/.cursor/mcp.json
        })

        # VS Code
        (lib.mkIf (builtins.elem "vscode" cfg.mcp.clients) {
          # VS Code reads ~/.config/Code/User/mcp.json on Linux
        })

        # Windsurf
        (lib.mkIf (builtins.elem "windsurf" cfg.mcp.clients) {
          # Windsurf reads ~/.windsurf/mcp.json
        })
      ]
    );
  };
}
