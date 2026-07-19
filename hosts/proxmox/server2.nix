# Proxmox third control-plane (etcd quorum).
{ config, ... }:
let
  settings = import ./settings.nix;
in
{
  imports = [
    ../profiles/proxmox.nix
    ../sops-token.nix
    ./bootstrap-hosts.nix
  ];

  networking.hostName = "server2";

  users.users.root.openssh.authorizedKeys.keys = settings.adminSshKeys;

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    server = {
      enable = true;
      bootstrap = false;
      joinUrl = "https://${settings.bootstrapHost}:9345";
      tokenFile = config.sops.secrets.rke2-token.path;
      tlsSans = [
        "server2"
        settings.bootstrapHost
      ];
    };
  };
}
