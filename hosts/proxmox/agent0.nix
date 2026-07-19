# Proxmox agent (baked qcow2).
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

  networking.hostName = "agent0";

  users.users.root.openssh.authorizedKeys.keys = settings.adminSshKeys;

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    agent = {
      enable = true;
      joinUrl = "https://${settings.bootstrapHost}:9345";
      tokenFile = config.sops.secrets.rke2-token.path;
    };
  };
}
