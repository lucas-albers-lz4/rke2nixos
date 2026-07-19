# Proxmox bootstrap control-plane (baked qcow2).
{ config, pkgs, lib, ... }:
let
  settings = import ./settings.nix;
in
{
  imports = [
    ../profiles/proxmox.nix
    ../sops-token.nix
    (import ./static-address.nix {
      inherit lib;
      address = settings.server0Ip;
      gateway = settings.gateway;
    })
  ];

  networking.hostName = "server0";

  environment.systemPackages = [ pkgs.vim ];

  users.users.root.openssh.authorizedKeys.keys = settings.adminSshKeys;

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    server = {
      enable = true;
      bootstrap = true;
      tokenFile = config.sops.secrets.rke2-token.path;
      nodeIP = settings.server0Ip;
      tlsSans = [
        "server0"
        settings.bootstrapHost
        settings.server0Ip
      ]
      ++ (if settings.clusterVip != "" then [ settings.clusterVip ] else [ ]);
    };

    vip = {
      enable = settings.clusterVip != "";
      virtualIp = settings.clusterVip;
      priority = 200;
      unicastSrcIp = settings.server0Ip;
      unicastPeers = [
        settings.server1Ip
        settings.server2Ip
      ];
    };
  };
}
