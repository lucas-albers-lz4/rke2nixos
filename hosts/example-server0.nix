# Bootstrap control-plane (cluster-init). Join endpoint for others: this host :9345.
# QEMU / CI path: lab token. Deploy path: hosts/proxmox/topology.nix or hosts/bare-metal/.
{ ... }:
{
  imports = [
    ./profiles/qemu.nix
    ./lab-token.nix
  ];

  networking.hostName = "server0";

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    server = {
      enable = true;
      bootstrap = true;
      tokenFile = "/etc/rancher/rke2/token";
      tlsSans = [
        "server0"
        "127.0.0.1"
      ];
    };
  };
}
