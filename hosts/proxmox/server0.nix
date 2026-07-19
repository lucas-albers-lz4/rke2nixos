# Proxmox bootstrap control-plane (baked qcow2).
{ config, pkgs, ... }:
let
  settings = import ./settings.nix;
  joinAddr = if settings.clusterVip != "" then settings.clusterVip else settings.bootstrapHost;
in
{
  imports = [
    ../profiles/proxmox.nix
    ../sops-token.nix
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
      tlsSans = [
        "server0"
        settings.bootstrapHost
      ]
      ++ (if settings.clusterVip != "" then [ settings.clusterVip ] else [ ]);
    };

    vip = {
      enable = settings.clusterVip != "";
      virtualIp = settings.clusterVip;
      priority = 200; # prefer bootstrap as MASTER
      unicastSrcIp = settings.server0Ip;
      unicastPeers = [
        settings.server1Ip
        settings.server2Ip
      ];
    };
  };
}
