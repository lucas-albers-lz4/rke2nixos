{
  config,
  lib,
  ...
}:
let
  cfg = config.rke2nixos.agent;
in
{
  options.rke2nixos.agent = {
    enable = lib.mkEnableOption "RKE2 agent (worker) role";

    joinUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "https://192.168.1.10:9345";
      description = "Supervisor URL of a control-plane server (port 9345).";
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      description = ''
        Path to the cluster (or agent) token file. Prefer sops-nix.
        Strings are allowed for runtime paths not present in the Nix store.
      '';
    };

    token = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Join token (store-visible — tests only). Prefer tokenFile.";
    };

    nodeName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "RKE2 node name. Must match networking.hostName (lowercase).";
    };

    nodeLabel = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "node.kubernetes.io/instance-type=worker"
        "workload.type=mixed"
      ];
      description = "Kubelet node labels.";
    };

    nodeIP = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Address to advertise for this node.";
    };

    extraFlags = lib.mkOption {
      type = with lib.types; either str (listOf str);
      default = [ ];
      description = "Extra flags passed to rke2 agent.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.joinUrl != "";
        message = "rke2nixos.agent: joinUrl is required";
      }
      {
        assertion = cfg.tokenFile != null || cfg.token != "";
        message = "rke2nixos.agent: set tokenFile (preferred) or token";
      }
    ];

    services.rke2 = {
      enable = true;
      role = "agent";
      serverAddr = cfg.joinUrl;
      tokenFile = cfg.tokenFile;
      token = cfg.token;
      nodeName = if cfg.nodeName != null then cfg.nodeName else config.networking.hostName;
      nodeLabel = cfg.nodeLabel;
      nodeIP = cfg.nodeIP;
      extraFlags = lib.flatten [ cfg.extraFlags ];
    };
  };
}
