# Bare-metal agent. Point joinUrl at the bootstrap node IP.
{ config, ... }:
{
  imports = [
    ../profiles/bare-metal.nix
    ../sops-token.nix
  ];

  networking.hostName = "agent0";

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    agent = {
      enable = true;
      joinUrl = "https://server0:9345";
      tokenFile = config.sops.secrets.rke2-token.path;
    };
  };
}
