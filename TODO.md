# Next steps / runway status

## Done (R0–R7 scaffolding)

| Phase | Status |
|-------|--------|
| R0 flake + QEMU + Docker/CI toplevels | Done |
| R1 sops-nix | Done — `./scripts/sops-bootstrap.sh`, encrypted `secrets/rke2-token.enc.yaml`, deploy hosts use `hosts/sops-token.nix`; QEMU examples keep `hosts/lab-token.nix`; tests use `tests/lib.nix` |
| R2 interactive VM smoke | Done — `./scripts/smoke-vms.sh`, [docs/interactive-vms.md](docs/interactive-vms.md) |
| R3 baked images | Done — `proxmox-*-qcow2`, `installer-iso` packages + CI |
| R4 host profiles | Done — `hosts/profiles/{qemu,proxmox,bare-metal,iso}.nix` |
| R5 live deploy runbooks | Done — [docs/deploy-proxmox.md](docs/deploy-proxmox.md), [docs/deploy-bare-metal.md](docs/deploy-bare-metal.md), `scripts/proxmox-import.sh` |
| R6 HA + etcd drill | Scaffolding done — [docs/etcd-rebuild.md](docs/etcd-rebuild.md), `three-server` check, proxmox server1/2 configs; **live join/drill still open** |
| R7 day-2 updates | Done — `scripts/deploy-host.sh`, [docs/day2-updates.md](docs/day2-updates.md); **live** no-wipe deploy exercised on Proxmox 1+1 |

## Operator checklist (on your Proxmox / metal)

| # | Item | Live status |
|---|------|-------------|
| 0 | Proxmox deploy role + API token ([docs/proxmox-rbac.md](docs/proxmox-rbac.md)) | Done |
| 0b | Node SSH ops user `rke2ops` for `qm guest` (L11/L7/L8/L9; L12 unused for lab) | Done |
| 1 | Age key on nodes (`/var/lib/sops-nix/key.txt`) | Done (cidata ISO / cloud-init) |
| 2 | Bake/import qcow2; server0 + agent0 Ready | Done |
| 3 | Join server1/server2; etcd replace drill | **Done** (2026-07-19: 3 CP Ready on L11/L7/L8; etcd replace of server2) |
| 4 | `./scripts/deploy-host.sh` no-wipe day-2 | Done (vim on proxmox-server0/agent0) |

## Design / architect review

Canonical draft (revised after [issue #1](https://github.com/lucas-albers-lz4/rke2nixos/issues/1)):

- [docs/design/operating-model-and-upgrades.md](docs/design/operating-model-and-upgrades.md)

**Locked decisions (summary):** `nixpkgs-rke2` flake input as the RKE2 pin; VIP/LB in Phase B; rolling = scripted inventory; SSH first-class.

**Phase B status (2026-07-19):** `nixpkgs-rke2` landed; CI lockfile guard; `rolling-upgrade.sh`; live pin deploy; VIP `192.168.1.29`; live R6 + etcd drill Done.

## Paused — resume here (live R6)


~~Paused for unrelated planning/design work.~~ **Live R6 + etcd drill completed 2026-07-19.**

### Current lab snapshot

| VMID | Role | Node | MEM | ens18 IPv4 |
|------|------|------|-----|------------|
| 200 | server0 | L11 | 3072 | sticky `.24` + DHCP `.32` |
| 201 | agent0 | L11 | 2048 | sticky `.25` + DHCP `.33` |
| 202 | server1 | L7 | 3072 | DHCP `.36` |
| 203 | server2 | L8 | 3072 | DHCP `.35` |

**Hypervisors:** L11=`192.168.1.11`, L7=`.7`, L8=`.8`, L9=`.9` (spare). **L12** unused for lab (low memory).

- Sticky bootstrap: `192.168.1.24` — still valid
- **Cluster VIP:** `192.168.1.29` (keepalived unicast; do not use `.20` — LAN conflict)
- Guest SSH: `root@192.168.1.{24,25,36,35}`
- Inventory: [`hosts/proxmox/inventory.nix`](hosts/proxmox/inventory.nix)

## Paused — next runway

Phase B pin/VIP/R6 live work completed. Later: optional thin `upgrade-rke2` CLI, host generator, Cilium (Phase D).


## Phase 2 / design Phase D (deferred — not on R1–R7 path)

Aligned with [docs/design/operating-model-and-upgrades.md](docs/design/operating-model-and-upgrades.md) §8:

- Cilium + `disable-kube-proxy` + HelmChartConfig
- Raspberry Pi / `nixos-hardware`
- `registries.yaml` helper
- deploy-rs / colmena (optional; nixos-rebuild is enough for R7)
- Mandatory host generation from a node list (optional generator may land earlier in Phase B)
- QEMU checks in Docker / GitHub-hosted CI

**Moved earlier (design Phase B — before durable HA join):** VIP/LB for join URL (flake-declared); see design doc. Until then: sticky `bootstrapHost` + runbook; no production claim on sticky-host join.
