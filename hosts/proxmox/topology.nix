# Canonical Proxmox lab topology (single source of truth).
# Edit nodes / clusterVip / keys here — not settings.nix or per-host files.
# Derived: bootstrapHost, inventory (rolling-upgrade), unicastPeers, tlsSans, joinUrl.
let
  nodes = [
    {
      name = "server0";
      role = "server";
      bootstrap = true;
      ip = "192.168.1.32";
      vipPriority = 200;
    }
    {
      name = "server1";
      role = "server";
      bootstrap = false;
      ip = "192.168.1.36";
      vipPriority = 150;
    }
    {
      name = "server2";
      role = "server";
      bootstrap = false;
      ip = "192.168.1.35";
      vipPriority = 100;
    }
    {
      name = "agent0";
      role = "agent";
      ip = "192.168.1.25";
    }
  ];

  servers = builtins.filter (n: n.role == "server") nodes;
  bootstrapNode =
    let
      matches = builtins.filter (n: n.bootstrap or false) servers;
    in
    if matches == [ ] then
      throw "hosts/proxmox/topology.nix: need exactly one server with bootstrap = true"
    else
      builtins.head matches;
in
{
  # Cluster VIP for join/API (keepalived unicast). Do not use .20 on this LAN.
  clusterVip = "192.168.1.29";

  gateway = "192.168.1.1";

  adminSshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILjCUGV97GhdCgKFTpu4PzjF0BS/7c8OXbUDsHCoBnzx lalbers@lalbers-X470-AORUS-ULTRA-GAMING"
  ];

  inherit nodes servers;

  # Break-glass join / tlsSan when VIP is down (bootstrap CP static IP).
  bootstrapHost = bootstrapNode.ip;
  bootstrapName = bootstrapNode.name;
}
