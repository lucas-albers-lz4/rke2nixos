# Proxmox agent (baked qcow2).
{ config, pkgs, ... }:
let
  settings = import ./settings.nix;
  joinHost = if settings.clusterVip != "" then settings.clusterVip else settings.bootstrapHost;
in
{
  imports = [
    ../profiles/proxmox.nix
    ../sops-token.nix
    ./bootstrap-hosts.nix
  ];

  networking.hostName = "agent0";

  environment.systemPackages = [ pkgs.vim ];

  users.users.root.openssh.authorizedKeys.keys = settings.adminSshKeys;

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    agent = {
      enable = true;
      joinUrl = "https://${joinHost}:9345";
      tokenFile = config.sops.secrets.rke2-token.path;
    };
  };
}
