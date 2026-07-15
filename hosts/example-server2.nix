# Third control-plane for etcd quorum (phase 1.5).
# Same join semantics as example-server1.
{ ... }:
{
  imports = [ ./qemu-profile.nix ];

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

  system.activationScripts.rke2LabToken.text = ''
    if [ ! -f /etc/rancher/rke2/token ]; then
      mkdir -p /etc/rancher/rke2
      umask 077
      echo "lab-cluster-token-change-me" > /etc/rancher/rke2/token
    fi
  '';
}
