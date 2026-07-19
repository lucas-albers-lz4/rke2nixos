# Proxmox bootstrap control-plane (baked qcow2).
{ config, pkgs, ... }:
let
  settings = import ./settings.nix;
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
      ];
    };
  };
}
