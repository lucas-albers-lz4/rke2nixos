# Shared sops-nix wiring for the RKE2 cluster token (deploy-shaped hosts).
# Place secrets/age.key contents at /var/lib/sops-nix/key.txt on the target
# (or inject before first boot). Build/deploy hosts need SOPS_AGE_KEY_FILE set
# when evaluating configurations that decrypt secrets.
{ config, ... }:
{
  sops.defaultSopsFile = ../secrets/rke2-token.enc.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.secrets.rke2-token = {
    mode = "0400";
    owner = "root";
  };
}
