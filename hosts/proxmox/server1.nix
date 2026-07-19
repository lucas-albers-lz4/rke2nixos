# Proxmox joining control-plane (HA).
{ config, lib, ... }:
let
  settings = import ./settings.nix;
in
{
  imports = [
    ../profiles/proxmox.nix
    ../sops-token.nix
    ./bootstrap-hosts.nix
    (import ./static-address.nix {
      inherit lib;
      address = settings.server1Ip;
      gateway = settings.gateway;
    })
  ];

  networking.hostName = "server1";

  users.users.root.openssh.authorizedKeys.keys = settings.adminSshKeys;

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    server = {
      enable = true;
      bootstrap = false;
      joinUrl =
        if settings.clusterVip != "" then
          "https://${settings.clusterVip}:9345"
        else
          "https://${settings.bootstrapHost}:9345";
      tokenFile = config.sops.secrets.rke2-token.path;
      nodeIP = settings.server1Ip;
      tlsSans = [
        "server1"
        settings.bootstrapHost
        settings.server1Ip
      ]
      ++ (if settings.clusterVip != "" then [ settings.clusterVip ] else [ ]);
    };

    vip = {
      enable = settings.clusterVip != "";
      virtualIp = settings.clusterVip;
      priority = 150;
      unicastSrcIp = settings.server1Ip;
      unicastPeers = [
        settings.server0Ip
        settings.server2Ip
      ];
    };
  };
}
