# Derived rolling-upgrade inventory from topology.nix — do not edit IPs here.
# Canonical edits: hosts/proxmox/topology.nix
let
  topology = import ./topology.nix;

  mkCp = n: {
    config = "proxmox-${n.name}";
    target = "root@${n.ip}";
    nodeName = n.name;
    bootstrap = n.bootstrap or false;
  };

  mkAgent = n: {
    config = "proxmox-${n.name}";
    target = "root@${n.ip}";
    nodeName = n.name;
  };
in
{
  controlPlanes = map mkCp topology.servers;
  agents = map mkAgent (builtins.filter (n: n.role == "agent") topology.nodes);
}
