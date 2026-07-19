# Proxmox third control-plane (etcd quorum).
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
      address = settings.server2Ip;
      gateway = settings.gateway;
    })
  ];

  networking.hostName = "server2";

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
      nodeIP = settings.server2Ip;
      tlsSans = [
        "server2"
        settings.bootstrapHost
        settings.server2Ip
      ]
      ++ (if settings.clusterVip != "" then [ settings.clusterVip ] else [ ]);
    };

    vip = {
      enable = settings.clusterVip != "";
      virtualIp = settings.clusterVip;
      priority = 100;
      unicastSrcIp = settings.server2Ip;
      unicastPeers = [
        settings.server0Ip
        settings.server1Ip
      ];
    };
  };
}
