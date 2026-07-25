# Reference lab (author Proxmox fleet)

This document is the **live testing** map for the repository maintainers. New users should start at [getting-started.md](getting-started.md) and use their own IPs — do not cargo-cult these addresses.

Canonical topology: [`hosts/proxmox/topology.nix`](../hosts/proxmox/topology.nix).

## Hypervisors

| Name | Management IP | Notes |
|------|---------------|--------|
| L11 | `192.168.1.11` | Primary; often holds server0 + agent0 |
| L7 | `192.168.1.7` | HA CP (e.g. server1) |
| L8 | `192.168.1.8` | HA CP (e.g. server2) |
| L9 | `192.168.1.9` | Spare |
| L12 | `192.168.1.12` | Unused for this lab (memory) |

Ops SSH for `qm guest`: `rke2ops@192.168.1.{11,7,8,9}`.

## Current lab snapshot

| VMID | Role | Node | MEM (MiB) | ens18 IPv4 |
|------|------|------|-----------|------------|
| 200 | server0 | L11 | 3072 | static `.32` |
| 201 | agent0 | L11 | 2048 | static `.25` |
| 202 | server1 | L7 | 3072 | static `.36` |
| 203 | server2 | L8 | 3072 | static `.35` |
| 210 | golden template | L11 | 2048 | template (clone source) |

- **Cluster VIP:** `192.168.1.29` (keepalived unicast)
- **Break-glass bootstrap:** `192.168.1.32` (`bootstrapHost` from topology)
- Guest SSH (CPs): `root@192.168.1.{32,36,35}`

## Import examples (lab)

```bash
PROXMOX_NODE=L11 PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh proxmox-server0-qcow2 200
PROXMOX_NODE=L11 ./scripts/proxmox-import.sh proxmox-agent0-qcow2 201
PROXMOX_NODE=L7 PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh proxmox-server1-qcow2 202
PROXMOX_NODE=L8 PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh proxmox-server2-qcow2 203
```

Verify free RAM before stacking CPs (other guests may already use ~8–9 GiB).

## Addressing notes

- Named hosts: Nix [`static-address.nix`](../hosts/proxmox/static-address.nix) (cloud-init net disabled on guest).
- Golden clones: nocloud `network-config` inside the age ISO + Proxmox `ipconfig0` UI parity — [golden-agent.md](golden-agent.md).
- Campaigns 1–3 (static CP, VIP failover, agent sticky vs DHCP): see [`TODO.md`](../TODO.md).

## Safety for `init-cluster.sh`

Running `./scripts/init-cluster.sh` **without** `--from-example` in this clone leaves `topology.nix` untouched (secrets only). Only use `--from-example` if you intentionally want to replace the lab topology (it writes a timestamped `.bak`).

## Related

- Generic deploy steps: [deploy-proxmox.md](deploy-proxmox.md)
- Day-2 / rolling: [day2-updates.md](day2-updates.md)
- Etcd replace drill: [etcd-rebuild.md](etcd-rebuild.md)
