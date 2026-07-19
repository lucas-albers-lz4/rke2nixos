# Proxmox agent (baked qcow2).
{ config, pkgs, lib, ... }:
let
  settings = import ./settings.nix;
  joinHost = if settings.clusterVip != "" then settings.clusterVip else settings.bootstrapHost;
in
{
  imports = [
    ../profiles/proxmox.nix
    ../sops-token.nix
    ./bootstrap-hosts.nix
    # Campaign 3 lab default: one static IPv4 (no DHCP dual-stack / float).
    (import ./static-address.nix {
      inherit lib;
      address = settings.agent0Ip;
      gateway = settings.gateway;
    })
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
      nodeIP = settings.agent0Ip;
    };
  };
}
