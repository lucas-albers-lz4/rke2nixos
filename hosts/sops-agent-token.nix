# sops-nix wiring for the RKE2 *agent* join token (golden workers only).
# Do NOT import on control-plane hosts. Never put the server/cluster token here.
# Place secrets/age.key at /var/lib/sops-nix/key.txt on the guest (cidata).
{ config, ... }:
{
  sops.defaultSopsFile = ../secrets/rke2-agent-token.enc.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.secrets.rke2-agent-token = {
    mode = "0400";
    owner = "root";
  };
}
