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
| R6 HA + etcd drill | Done — [docs/etcd-rebuild.md](docs/etcd-rebuild.md), `three-server` check, proxmox server1/2 configs |
| R7 day-2 updates | Done — `scripts/deploy-host.sh`, [docs/day2-updates.md](docs/day2-updates.md); **live** no-wipe deploy exercised on Proxmox 1+1 |

## Operator checklist (on your Proxmox / metal)

| # | Item | Live status |
|---|------|-------------|
| 0 | Proxmox deploy role + API token ([docs/proxmox-rbac.md](docs/proxmox-rbac.md)) | Done |
| 0b | Node SSH ops user `rke2ops` for `qm guest cmd` (L11=`192.168.1.11`) | Done |
| 1 | Age key on nodes (`/var/lib/sops-nix/key.txt`) | Done (cidata ISO / cloud-init) |
| 2 | Bake/import qcow2; server0 + agent0 Ready | Done |
| 3 | Join server1/server2; etcd replace drill | Open |
| 4 | `./scripts/deploy-host.sh` no-wipe day-2 | Done (vim on proxmox-server0/agent0) |

## Phase 2 (deferred — not on R1–R7 path)

- Cilium + `disable-kube-proxy` + HelmChartConfig
- Raspberry Pi / `nixos-hardware`
- `registries.yaml` helper
- deploy-rs / colmena (optional; nixos-rebuild is enough for R7)
- VIP/LB for join URL
- QEMU checks in Docker / GitHub-hosted CI
