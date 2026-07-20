# Golden Proxmox agent (Tier 2)

One Nix-built qcow2 (`proxmox-golden-agent-qcow2`); per-clone identity at first boot via cidata + Proxmox `ipconfig0`. Design: [issue #4](https://github.com/lucas-albers-lz4/rke2nixos/issues/4).

## Constraints

- **Agent-token only** in the image (`hosts/sops-agent-token.nix` → `secrets/rke2-agent-token.enc.yaml`). Never the server/cluster token module.
- **No token in cidata** — age key only; sops decrypts the agent token on the guest.
- **Stateless workers only** — no local PVs / nodeName-pinned workloads on clone-replace cattle.
- **Manual topology** — after Ready, add a row to [`hosts/proxmox/topology.nix`](../hosts/proxmox/topology.nix) before the next `rolling-upgrade.sh`.
- **New disk = new node** — full clone; do not reuse a disk that already joined under another hostname (identity unit fails closed).

## Prep secrets

```bash
# Dedicated agent-token preferred. Lab shortcut (same value, separate sops file):
./scripts/sops-bootstrap.sh --agent-token --from-cluster-token

# Or set RKE2_AGENT_TOKEN=… then:
# ./scripts/sops-bootstrap.sh --agent-token
```

On control planes, configure the matching RKE2 agent-token if it differs from the server token.

## Bake + import template

```bash
nix build .#packages.x86_64-linux.proxmox-golden-agent-qcow2 --out-link result-golden-agent
./scripts/proxmox-import.sh ./result-golden-agent/nixos.qcow2 210 local-lvm rke2nixos-golden-template
# Convert VM 210 to a template in the Proxmox UI (or leave as clone source).
```

Re-bake when `nixpkgs-rke2` moves in `flake.lock`.

## Clone a worker

```bash
# Full clone to a new VMID/disk (example: 211).
# Then attach identity cidata + static IP:
export PROXMOX_HOSTNAME_211=agent1
export PROXMOX_JOIN_URL_211=https://192.168.1.29:9345   # optional; defaults to topology VIP
export PROXMOX_IPCONFIG_211='ip=192.168.1.40/24,gw=192.168.1.1'
./scripts/proxmox-age-cloudinit.sh 211
# Cold boot 211 → wait Ready
```

## Register for day-2

Add to `hosts/proxmox/topology.nix` `nodes` (example):

```nix
{ name = "agent1"; role = "agent"; ip = "192.168.1.40"; }
```

Then `./scripts/rolling-upgrade.sh --dry-run` should list the new agent.

## Decommission

1. `kubectl delete node <name>`
2. Destroy the VM (and disk)
3. Remove the topology row

## Stale disk

If identity fails with “stale agent state”, the disk previously joined as another name. Destroy/reclone, or wipe `/var/lib/rancher/rke2` + `/etc/rancher/node` only after the Kubernetes node object is gone.
