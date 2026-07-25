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

Host Nix often lacks flakes; qcow2 bake also needs KVM. Prefer Docker Nix and copy the image out in the **same** run (container store is ephemeral):

```bash
NIX_DOCKER_EXTRA_ARGS='--device /dev/kvm' ./scripts/nix-docker.sh bash -lc '
  set -euo pipefail
  mkdir -p /work/artifacts
  nix build .#packages.x86_64-linux.proxmox-golden-agent-qcow2 --out-link /tmp/golden-out
  f=$(find "$(readlink -f /tmp/golden-out)" -name "*.qcow2" | head -1)
  cp -L "$f" /work/artifacts/proxmox-golden-agent.qcow2
'

# Or with host Nix (if flakes + nix-command enabled and /dev/kvm usable):
# nix build .#packages.x86_64-linux.proxmox-golden-agent-qcow2 --out-link result-golden-agent

./scripts/proxmox-import.sh ./artifacts/proxmox-golden-agent.qcow2 210 local-lvm rke2nixos-golden-template
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

`PROXMOX_IPCONFIG_*` is written into the age cidata ISO as nocloud `network-config`
(and mirrored as Proxmox `ipconfig0` for the UI). Cloud-init binds a single seed;
with both ide3 (age) and ide2 (Proxmox), the age ISO wins — so static IP must live
in the age ISO or the guest falls back to DHCP.

## Lab PoC notes (2026-07-24)

- Template VMID `210` (`rke2nixos-golden-template`) left on L11 for reuse.
- PoC clone `211` / `agent1` / `.40` joined Ready, then decommissioned.
- Bugs found and fixed in-tree (rebake golden before next cold clone):
  1. Dual cidata: embed `network-config` in age ISO (`proxmox-age-cloudinit.sh`).
  2. Identity oneshot: use `writeShellApplication` runtime PATH (`ip`/`tr`); transient hostname on immutable `/etc/hostname`.

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
