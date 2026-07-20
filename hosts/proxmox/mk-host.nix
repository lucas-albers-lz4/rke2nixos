# Generate a Proxmox NixOS module from topology + one node attr.
# Usage: import ./mk-host.nix topology node
topology: node:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (topology) clusterVip gateway adminSshKeys bootstrapHost bootstrapName servers;

  joinHost = if clusterVip != "" then clusterVip else bootstrapHost;
  joinUrl = "https://${joinHost}:9345";

  isServer = node.role == "server";
  isBootstrap = isServer && (node.bootstrap or false);
  isAgent = node.role == "agent";

  unicastPeers = map (n: n.ip) (builtins.filter (n: n.name != node.name) servers);

  tlsSans = lib.unique (
    [
      node.name
      bootstrapHost
      node.ip
    ]
    ++ lib.optional (clusterVip != "") clusterVip
  );
in
assert builtins.match "[a-z0-9]([a-z0-9-]*[a-z0-9])?" node.name != null
|| throw "proxmox node name must be lowercase hostname-safe: ${node.name}";
assert isServer || isAgent || throw "proxmox node ${node.name}: role must be server or agent";
{
  imports = [
    ../profiles/proxmox.nix
    ../sops-token.nix
    (import ./static-address.nix {
      inherit lib;
      address = node.ip;
      gateway = gateway;
    })
  ]
  ++ lib.optionals (!isBootstrap) [
    (import ./bootstrap-hosts.nix {
      inherit lib;
      inherit bootstrapHost bootstrapName;
    })
  ];

  networking.hostName = node.name;

  environment.systemPackages = [ pkgs.vim ];

  users.users.root.openssh.authorizedKeys.keys = adminSshKeys;

  rke2nixos = {
    cni = "canal";
    preloadImages = false;

    server = lib.mkIf isServer {
      enable = true;
      bootstrap = isBootstrap;
      joinUrl = lib.mkIf (!isBootstrap) joinUrl;
      tokenFile = config.sops.secrets.rke2-token.path;
      nodeIP = node.ip;
      tlsSans = tlsSans;
    };

    agent = lib.mkIf isAgent {
      enable = true;
      joinUrl = joinUrl;
      tokenFile = config.sops.secrets.rke2-token.path;
      nodeIP = node.ip;
    };

    vip = lib.mkIf isServer {
      enable = clusterVip != "";
      virtualIp = clusterVip;
      priority = node.vipPriority or 100;
      unicastSrcIp = node.ip;
      unicastPeers = unicastPeers;
    };
  };
}
