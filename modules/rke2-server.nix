{
  config,
  lib,
  ...
}:
let
  cfg = config.rke2nixos.server;
  defaults = config.rke2nixos;
in
{
  options.rke2nixos.server = {
    enable = lib.mkEnableOption "RKE2 control-plane (server) role";

    bootstrap = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        First control-plane node. When true, do not set serverAddr (cluster-init).
        When false, this server joins an existing cluster via joinUrl.
      '';
    };

    joinUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "https://192.168.1.10:9345";
      description = ''
        Supervisor URL of the bootstrap (or VIP) server. Required when bootstrap = false.
        Sticky bootstrap IP is fine for 1+1; introduce a VIP before relying on HA without node0.
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      description = ''
        Path to the shared cluster token file. Prefer sops-nix decrypted secrets.
        Never regenerate after first bootstrap — rebuilds must reuse the same token.
        Strings are allowed for runtime paths (e.g. /run/secrets/...) that are not in the Nix store.
      '';
    };

    token = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Cluster token (world-readable in the Nix store — tests only). Prefer tokenFile.";
    };

    agentTokenFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      description = "Optional separate agent token file.";
    };

    nodeName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "RKE2 node name. Must match networking.hostName (lowercase).";
    };

    tlsSans = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "rke2.example.com"
        "10.0.0.10"
      ];
      description = "Additional TLS SANs for the API server (--tls-san).";
    };

    nodeLabel = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "node.kubernetes.io/instance-type=control-plane"
        "workload.type=control-plane"
      ];
      description = "Kubelet node labels.";
    };

    nodeIP = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Address to advertise for this node. Set in QEMU tests to the primary IP.";
    };

    extraFlags = lib.mkOption {
      type = with lib.types; either str (listOf str);
      default = [ ];
      description = "Extra flags passed to rke2 server.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.bootstrap || cfg.joinUrl != "";
        message = "rke2nixos.server: joinUrl is required when bootstrap = false";
      }
      {
        assertion = cfg.tokenFile != null || cfg.token != "";
        message = "rke2nixos.server: set tokenFile (preferred) or token";
      }
    ];

    services.rke2 = {
      enable = true;
      role = "server";
      package = defaults.package;
      tokenFile = cfg.tokenFile;
      token = cfg.token;
      agentTokenFile = cfg.agentTokenFile;
      serverAddr = lib.mkIf (!cfg.bootstrap) cfg.joinUrl;
      nodeName = if cfg.nodeName != null then cfg.nodeName else config.networking.hostName;
      nodeLabel = cfg.nodeLabel;
      nodeIP = cfg.nodeIP;
      extraFlags =
        (map (san: "--tls-san=${san}") cfg.tlsSans)
        ++ (lib.flatten [ cfg.extraFlags ]);
    };
  };
}
