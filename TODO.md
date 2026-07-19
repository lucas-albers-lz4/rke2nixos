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
| 0b | Node SSH ops user `rke2ops` for `qm guest cmd` (L11=`192.168.1.11`, L12=`192.168.1.12`) | Done |
| 1 | Age key on nodes (`/var/lib/sops-nix/key.txt`) | Done (cidata ISO / cloud-init) |
| 2 | Bake/import qcow2; server0 + agent0 Ready | Done |
| 3 | Join server1/server2; etcd replace drill | **Open — next when returning to this runway** |
| 4 | `./scripts/deploy-host.sh` no-wipe day-2 | Done (vim on proxmox-server0/agent0) |

## Design / architect review (in progress)

Canonical draft for external review of guidelines and day-2/upgrade philosophy:

- [docs/design/operating-model-and-upgrades.md](docs/design/operating-model-and-upgrades.md)

## Paused — resume here (live R6)


Paused for unrelated planning/design work. When returning, the next runway item is **live R6**.

### Current lab snapshot

| VMID | Role | Node | MEM | ens18 IPv4 (qm guest) |
|------|------|------|-----|------------------------|
| 200 | server0 | L11 | 3072 | `.32` DHCP + sticky `.24` |
| 201 | agent0 | L11 | 2048 | `.33` DHCP + sticky `.25` |

- Sticky join URL / `bootstrapHost`: `192.168.1.24` ([hosts/proxmox/settings.nix](hosts/proxmox/settings.nix))
- IP discovery: `ssh rke2ops@192.168.1.11 'sudo qm guest cmd <vmid> network-get-interfaces'`
- Guest SSH: prefer `root@192.168.1.24` / `root@192.168.1.25`
- CP needs ≥3 GiB (2 GiB left control-plane NotReady)

### Decisions to lock on resume

**Scope**

1. Full R6: bake/import server1+server2 → 3 Ready CPs → etcd replace drill ([docs/etcd-rebuild.md](docs/etcd-rebuild.md))
2. Join only (3 Ready CPs); defer etcd drill
3. Commit/push any uncommitted R7 leftovers first, then R6

**RAM layout** (hypervisor cannot hold 2×8 GiB; current guests ~5 GiB)

1. Keep agent; add two ~3 GiB CPs (~11 GiB total)
2. Stop agent temporarily; 3× ~3 GiB CPs only
3. Put server1/server2 on **L12**; keep 200/201 on L11
4. Custom sizes once free RAM is known

### Suggested resume sequence (after decisions)

1. Bake `proxmox-server1-qcow2` / `proxmox-server2-qcow2`
2. Import (VMIDs e.g. 202/203), age cidata ISO, `cpu=host`, CP memory ≥3072
3. Join via `https://192.168.1.24:9345` + shared sops token; confirm 3 Ready control-planes
4. Optional: etcd member replace drill on a non-bootstrap CP
5. Mark checklist item 3 Done

## Phase 2 (deferred — not on R1–R7 path)

- Cilium + `disable-kube-proxy` + HelmChartConfig
- Raspberry Pi / `nixos-hardware`
- `registries.yaml` helper
- deploy-rs / colmena (optional; nixos-rebuild is enough for R7)
- VIP/LB for join URL
- QEMU checks in Docker / GitHub-hosted CI
