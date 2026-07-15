# Bootstrap control-plane (cluster-init). Join endpoint for others: this host :9345.
{ ... }:
{
  imports = [ ./qemu-profile.nix ];

  networking.hostName = "server0";

  # Optional sops: decrypt secrets/rke2-token.enc.yaml → token path
  # sops.defaultSopsFile = ../secrets/rke2-token.enc.yaml;
  # sops.secrets.rke2-token = { };
  # Then: tokenFile = config.sops.secrets.rke2-token.path;

  rke2nixos = {
    cni = "canal";
    # Set true on airgapped / test nodes that should not pull from the network
    preloadImages = false;

    server = {
      enable = true;
      bootstrap = true;
      # REPLACE: use sops path in real deploys. Placeholder for evaluation only.
      tokenFile = "/etc/rancher/rke2/token";
      tlsSans = [
        "server0"
        "127.0.0.1"
      ];
      # Extra SANs for joining servers / agents as you grow the cluster
      # tlsSans = [ "server0" "server1" "server2" "10.0.0.10" ];
    };
  };

  # Seed a lab token if the file is missing (do NOT use in production).
  system.activationScripts.rke2LabToken.text = ''
    if [ ! -f /etc/rancher/rke2/token ]; then
      mkdir -p /etc/rancher/rke2
      umask 077
      echo "lab-cluster-token-change-me" > /etc/rancher/rke2/token
    fi
  '';
}
