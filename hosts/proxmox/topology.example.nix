# Example Proxmox topology for a new cluster (1 control-plane + 1 agent).
# Copy to topology.nix (or run ./scripts/init-cluster.sh), then replace placeholders.
#
# Live lab SoT for this repository remains topology.nix — do not commit personal
# secrets or LAN details into the example file.
#
# Derived by mk-host / inventory: bootstrapHost, unicastPeers, tlsSans, joinUrl.
let
  nodes = [
    {
      name = "server0";
      role = "server";
      bootstrap = true;
      # Documentation / TEST-NET-1 style addresses — replace with your LAN.
      ip = "192.0.2.10";
      vipPriority = 200;
    }
    {
      name = "agent0";
      role = "agent";
      ip = "192.0.2.20";
    }
  ];

  servers = builtins.filter (n: n.role == "server") nodes;
  bootstrapNode =
    let
      matches = builtins.filter (n: n.bootstrap or false) servers;
    in
    if matches == [ ] then
      throw "hosts/proxmox/topology.example.nix: need exactly one server with bootstrap = true"
    else
      builtins.head matches;
in
{
  # Prefer a free IP on your LAN for keepalived (join/API). Empty string disables VIP.
  clusterVip = "192.0.2.100";

  gateway = "192.0.2.1";

  adminSshKeys = [
    "REPLACE_SSH_KEY" # e.g. ssh-ed25519 AAAA… you@laptop
  ];

  inherit nodes servers;

  bootstrapHost = bootstrapNode.ip;
  bootstrapName = bootstrapNode.name;
}
