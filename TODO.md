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
| R7 day-2 updates | Done — `scripts/deploy-host.sh`, [docs/day2-updates.md](docs/day2-updates.md) |

## Operator checklist (on your Proxmox / metal)

Repo scaffolding is complete; confidence on **your** hardware still requires:

0. (Recommended) As Proxmox root once: `./scripts/proxmox-create-deploy-role.sh` → use the API token for day-to-day ([docs/proxmox-rbac.md](docs/proxmox-rbac.md))
1. Keep `secrets/age.key` private; install to `/var/lib/sops-nix/key.txt` on nodes
2. Bake/import qcow2; bring up server0 + agent0
3. Join server1/server2; run the etcd replace drill once
4. Exercise `./scripts/deploy-host.sh` for a no-wipe config change

## Phase 2 (deferred — not on R1–R7 path)

- Cilium + `disable-kube-proxy` + HelmChartConfig
- Raspberry Pi / `nixos-hardware`
- `registries.yaml` helper
- deploy-rs / colmena (optional; nixos-rebuild is enough for R7)
- VIP/LB for join URL
- QEMU checks in Docker / GitHub-hosted CI
