{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.rke2nixos;
in
{
  options.rke2nixos = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rke2;
      defaultText = lib.literalExpression "pkgs.rke2";
      description = "RKE2 package (e.g. pkgs.rke2, pkgs.rke2_1_33, pkgs.rke2_latest).";
    };

    cni = lib.mkOption {
      type = lib.types.enum [
        "canal"
        "calico"
        "cilium"
        "flannel"
        "none"
      ];
      default = "canal";
      description = ''
        CNI plugin. v1 defaults to canal (RKE2 default, simplest for QEMU).
        Cilium + kube-proxy replacement is deferred to phase 2.
      '';
    };

    disable = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "rke2-ingress-nginx" ];
      description = "RKE2 packaged components to disable via --disable.";
    };

    preloadImages = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, stage arch-correct RKE2 core + CNI image archives into
        /var/lib/rancher/rke2/agent/images before start (airgap / sandbox tests).
      '';
    };
  };

  config =
    let
      throwSystem = throw "rke2nixos: unsupported system ${pkgs.stdenv.hostPlatform.system}";
      archImages =
        let
          pkg = cfg.package;
          system = pkgs.stdenv.hostPlatform.system;
          core =
            {
              aarch64-linux = pkg.images-core-linux-arm64-tar-zst or null;
              x86_64-linux = pkg.images-core-linux-amd64-tar-zst or null;
            }
            .${system} or throwSystem;
          cniName =
            {
              canal = "canal";
              calico = "calico";
              cilium = "cilium";
              flannel = "flannel";
              none = null;
            }
            .${cfg.cni};
          cni =
            if cniName == null then
              null
            else
              {
                aarch64-linux = pkg."images-${cniName}-linux-arm64-tar-zst" or null;
                x86_64-linux = pkg."images-${cniName}-linux-amd64-tar-zst" or null;
              }
              .${system} or throwSystem;
        in
        lib.filter (x: x != null) [
          core
          cni
        ];
    in
    lib.mkIf (cfg.server.enable || cfg.agent.enable) {
      services.rke2.package = cfg.package;
      # CNI is a server-only flag; agents inherit the cluster CNI.
      services.rke2.cni = lib.mkIf cfg.server.enable cfg.cni;
      services.rke2.disable = lib.mkIf cfg.server.enable (lib.mkDefault cfg.disable);
      services.rke2.images = lib.mkIf cfg.preloadImages archImages;
    };
}
