# Golden Proxmox agent image: one Nix build, N clones via cidata identity.
# Does not import static-address.nix (cloud-init / Proxmox ipconfig0 owns networking).
# Token path is agent-token only — never hosts/sops-token.nix (server token).
{
  config,
  pkgs,
  lib,
  ...
}:
let
  topology = import ./topology.nix;
  joinHost = if topology.clusterVip != "" then topology.clusterVip else topology.bootstrapHost;
  defaultJoinUrl = "https://${joinHost}:9345";
in
{
  imports = [
    ../profiles/proxmox.nix
    ../sops-agent-token.nix
  ];

  # Placeholder; rke2nixos-agent-identity overwrites from cidata before rke2-agent.
  networking.hostName = "golden-agent";

  environment.systemPackages = [ pkgs.vim ];

  # Bake-time fallback if cidata omits /run/rke2nixos/join-url (cidata still wins).
  environment.etc."rke2nixos/default-join-url".text = "${defaultJoinUrl}\n";

  users.users.root.openssh.authorizedKeys.keys = topology.adminSshKeys;

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    agent = {
      enable = true;
      identityMode = "cloud-init";
      tokenFile = config.sops.secrets.rke2-agent-token.path;
      # joinUrl / nodeIP supplied at boot by identity oneshot (+ optional default above).
    };
  };
}
