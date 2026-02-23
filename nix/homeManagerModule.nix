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

    gateway = {
      enable = lib.mkEnableOption "RemoteJuggler MCP gateway (tsnet + Setec + additive resolution)";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.rj-gateway;
        defaultText = lib.literalExpression "pkgs.rj-gateway";
        description = "The rj-gateway package to install.";
      };

      setecUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Setec server URL on the tailnet.";
      };

      setecPrefix = lib.mkOption {
        type = lib.types.str;
        default = "remotejuggler/";
        description = "Prefix for secret names in Setec.";
      };

      setecSecrets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Secret names to pre-fetch and keep warm via background polling.";
      };

      precedence = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "env" "sops" "kdbx" "setec" ];
        description = "Source precedence order for additive credential resolution.";
      };

      tailscaleHostname = lib.mkOption {
        type = lib.types.str;
        default = "rj-gateway";
        description = "Tailscale hostname for the gateway node.";
      };

      localMode = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run gateway in local mode (no tsnet). Suitable for Claude Code on lab machines.";
      };

      listenAddr = lib.mkOption {
        type = lib.types.str;
        default = "localhost:8443";
        description = "Listen address when running in local mode.";
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
      ++ lib.optional (cfg.gui.enable && pkgs.stdenv.isLinux) cfg.gui.package
      ++ lib.optional cfg.gateway.enable cfg.gateway.package;

    xdg.configFile = let
      # MCP config with optional gateway
      mcpConfig = {
        mcpServers = {
          remote-juggler = {
            command = "${cfg.package}/bin/remote-juggler";
            args = [ "--mode=mcp" ];
          };
        } // lib.optionalAttrs cfg.gateway.enable {
          rj-gateway = if cfg.gateway.localMode then {
            command = "${cfg.gateway.package}/bin/rj-gateway";
            args = [
              "--listen=${cfg.gateway.listenAddr}"
              "--chapel-bin=${cfg.package}/bin/remote-juggler"
            ];
            env = {
              RJ_GATEWAY_LISTEN = cfg.gateway.listenAddr;
              RJ_GATEWAY_LOCAL = "1";
            } // lib.optionalAttrs (cfg.gateway.setecUrl != "") {
              RJ_GATEWAY_SETEC_URL = cfg.gateway.setecUrl;
            };
          } else {
            command = "${cfg.gateway.package}/bin/rj-gateway";
            args = [
              "--chapel-bin=${cfg.package}/bin/remote-juggler"
            ];
            env = lib.optionalAttrs (cfg.gateway.setecUrl != "") {
              RJ_GATEWAY_SETEC_URL = cfg.gateway.setecUrl;
            };
          };
        };
      };
      mcpJson = jsonFormat.generate "mcp-config.json" mcpConfig;

      # Gateway config file
      gatewayConfig = {
        listen = if cfg.gateway.localMode then cfg.gateway.listenAddr else ":443";
        chapel_binary = "${cfg.package}/bin/remote-juggler";
        setec_url = cfg.gateway.setecUrl;
        setec_prefix = cfg.gateway.setecPrefix;
        setec_secrets = cfg.gateway.setecSecrets;
        precedence = cfg.gateway.precedence;
        tailscale = {
          hostname = cfg.gateway.tailscaleHostname;
        };
      };
    in lib.mkMerge [
      # Write config.json if provided
      (lib.mkIf (cfg.config != null) {
        "remote-juggler/config.json".source =
          jsonFormat.generate "remote-juggler-config.json" cfg.config;
      })

      # Gateway config
      (lib.mkIf cfg.gateway.enable {
        "remote-juggler/gateway.json".source =
          jsonFormat.generate "rj-gateway-config.json" gatewayConfig;
      })

      # Claude Code MCP config -- writes to ~/.config/claude/mcp.json
      (lib.mkIf (cfg.mcp.enable && builtins.elem "claude-code" cfg.mcp.clients) {
        "remote-juggler/mcp-claude.json".source = mcpJson;
      })
    ];
  };
}
