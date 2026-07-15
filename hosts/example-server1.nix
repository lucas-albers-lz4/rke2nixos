# Joining control-plane for HA growth (phase 1.5).
# Enable after server0 is healthy; points at bootstrap :9345 (no VIP yet).
#
# Rebuild / replace rules once you have 3 servers:
#   1. From a surviving CP: remove etcd member + kubectl delete node
#   2. Rejoin with the SAME cluster token
#   3. Never rebuild the last remaining server without an etcd restore plan
{ ... }:
{
  imports = [ ./qemu-profile.nix ];

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

  system.activationScripts.rke2LabToken.text = ''
    if [ ! -f /etc/rancher/rke2/token ]; then
      mkdir -p /etc/rancher/rke2
      umask 077
      echo "lab-cluster-token-change-me" > /etc/rancher/rke2/token
    fi
  '';
}
