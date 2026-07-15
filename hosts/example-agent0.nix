# First agent (worker). Joins bootstrap server on :9345.
{ ... }:
{
  imports = [ ./qemu-profile.nix ];

  networking.hostName = "agent0";

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    agent = {
      enable = true;
      # Sticky join URL → bootstrap server. Replace with VIP when HA requires it.
      joinUrl = "https://server0:9345";
      tokenFile = "/etc/rancher/rke2/token";
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
