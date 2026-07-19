# Third control-plane for etcd quorum.
{ ... }:
{
  imports = [
    ./profiles/qemu.nix
    ./lab-token.nix
  ];

  networking.hostName = "server2";

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    server = {
      enable = true;
      bootstrap = false;
      joinUrl = "https://server0:9345";
      tokenFile = "/etc/rancher/rke2/token";
      tlsSans = [
        "server2"
        "server0"
      ];
    };
  };
}
