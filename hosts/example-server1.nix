# Joining control-plane for HA growth.
# Rebuild / replace rules: see docs/etcd-rebuild.md
{ ... }:
{
  imports = [
    ./profiles/qemu.nix
    ./lab-token.nix
  ];

  networking.hostName = "server1";

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    server = {
      enable = true;
      bootstrap = false;
      joinUrl = "https://server0:9345";
      tokenFile = "/etc/rancher/rke2/token";
      tlsSans = [
        "server1"
        "server0"
      ];
    };
  };
}
