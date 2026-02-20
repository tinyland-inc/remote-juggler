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

    xdg.configFile = let
      mcpConfig = {
        mcpServers.remote-juggler = {
          command = "${cfg.package}/bin/remote-juggler";
          args = [ "--mode=mcp" ];
        };
      };
      mcpJson = jsonFormat.generate "mcp-config.json" mcpConfig;
    in lib.mkMerge [
      # Write config.json if provided
      (lib.mkIf (cfg.config != null) {
        "remote-juggler/config.json".source =
          jsonFormat.generate "remote-juggler-config.json" cfg.config;
      })

      # Claude Code MCP config
      (lib.mkIf (cfg.mcp.enable && builtins.elem "claude-code" cfg.mcp.clients) {
        "remote-juggler/mcp-claude.json".source = mcpJson;
      })
    ];
  };
}
