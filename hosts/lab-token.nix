# Lab-only cluster token for QEMU example hosts and interactive VMs.
# Deploy-shaped hosts (Proxmox / bare metal) use hosts/sops-token.nix instead.
# QEMU nixosTests inject their own token via tests/lib.nix and do not import this.
{ ... }:
{
  system.activationScripts.rke2LabToken.text = ''
    if [ ! -f /etc/rancher/rke2/token ]; then
      mkdir -p /etc/rancher/rke2
      umask 077
      echo "lab-cluster-token-change-me" > /etc/rancher/rke2/token
    fi
  '';
}
