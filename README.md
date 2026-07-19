# Immutable RKE2 on NixOS

Generic flake that wraps upstream nixpkgs [`services.rke2`](https://github.com/NixOS/nixpkgs/tree/master/nixos/modules/services/cluster/rancher) for reproducible, multi-arch (x86_64 / aarch64) clusters. NixOS provides the immutable OS; RKE2 state stays mutable under `/var/lib/rancher/rke2`.

## Why this repo exists

nixpkgs already packages RKE2 and ships a full NixOS module (role, token, CNI, CIS, manifests, airgap images). This flake adds:

- Thin role wrappers (`rke2nixos.server` / `rke2nixos.agent`) with bootstrap vs join semantics
- Firewall, sysctl, hostname/`node-name` conventions
- Example hosts for **1 server + 1 agent → 3-server quorum**
- QEMU NixOS tests with preloaded image archives
- sops-nix cluster token, Proxmox qcow2 / installer ISO, day-2 `nixos-rebuild` deploy

It does **not** reimplement the RKE2 systemd unit.

## Deploy runway (R0–R7)

| Phase | What |
|-------|------|
| R0 | Flake, QEMU checks, Docker/CI toplevels |
| R1 | sops-nix token ([`scripts/sops-bootstrap.sh`](scripts/sops-bootstrap.sh)) |
| R2 | Interactive VM smoke ([docs/interactive-vms.md](docs/interactive-vms.md)) |
| R3 | Baked qcow2 + ISO packages |
| R4 | Host profiles: qemu / proxmox / bare-metal |
| R5 | Live bring-up runbooks ([docs/deploy-proxmox.md](docs/deploy-proxmox.md), [docs/deploy-bare-metal.md](docs/deploy-bare-metal.md)) |
| R6 | HA + etcd replace drill ([docs/etcd-rebuild.md](docs/etcd-rebuild.md)) |
| R7 | Day-2 updates ([docs/day2-updates.md](docs/day2-updates.md), [`scripts/deploy-host.sh`](scripts/deploy-host.sh)) |

## Quick start

Flakes need `nix-command` and `flakes` enabled. Prefer Nix-in-Docker for day-to-day work.

### Nix in Docker (preferred)

```bash
./scripts/nix-docker.sh nix flake show
./scripts/nix-docker.sh nix build .#packages.x86_64-linux.example-server0
./scripts/nix-docker.sh nix build .#packages.x86_64-linux.example-agent0
```

### Host Nix

```bash
nix flake show

# Lab toplevels (CI)
nix build .#packages.x86_64-linux.example-server0
nix build .#packages.x86_64-linux.example-agent0

# Baked images
nix build .#packages.x86_64-linux.proxmox-server0-qcow2
nix build .#packages.x86_64-linux.installer-iso

# QEMU checks: Linux host + KVM only
nix build .#checks.x86_64-linux.server-agent
nix build .#checks.x86_64-linux.single-node
nix build .#checks.x86_64-linux.three-server
```

### Interactive VMs

```bash
./scripts/smoke-vms.sh
nix run .#example-server0-vm
```

See [docs/interactive-vms.md](docs/interactive-vms.md) for multi-VM networking gaps.

## Layout

```
flake.nix
.sops.yaml
scripts/                 # nix-docker, sops-bootstrap, deploy-host, proxmox-*, smoke-vms
docs/proxmox-rbac.md     # least-privilege Proxmox role + API token
modules/                 # rke2nixos.* wrappers
hosts/
  profiles/              # qemu, proxmox, bare-metal, iso
  example-*.nix          # QEMU/CI lab (lab token)
  proxmox/               # sops-backed Proxmox hosts
  bare-metal/            # sops-backed metal hosts
tests/                   # nixosTest QEMU suites (test token)
secrets/                 # age.key (gitignored), rke2-token.enc.yaml
docs/                    # deploy, day-2, etcd, interactive VMs
```

## Bootstrap semantics

| Role | Config | Join |
|------|--------|------|
| Bootstrap server | `rke2nixos.server.bootstrap = true` | initializes cluster |
| Additional server | `bootstrap = false` + `joinUrl` | `https://server0:9345` + shared token |
| Agent | `rke2nixos.agent` | same `joinUrl` + token |

**Token:** generate once, store via sops-nix, reuse forever. Regenerating breaks joins and rebuilds.

**State:** declarative config under `/etc/rancher/rke2` (and Nix); mutable data under `/var/lib/rancher/rke2`.

## Secrets (sops-nix) — R1

```bash
./scripts/sops-bootstrap.sh          # age key + encrypt secrets/rke2-token.enc.yaml
./scripts/sops-bootstrap.sh --rotate-token  # only before first real bootstrap
```

- Public key in [`.sops.yaml`](.sops.yaml) / [`secrets/.sops.yaml`](secrets/.sops.yaml)
- Private key: `secrets/age.key` (gitignored) → on nodes as `/var/lib/sops-nix/key.txt`
- Deploy hosts import [`hosts/sops-token.nix`](hosts/sops-token.nix)
- QEMU example hosts keep [`hosts/lab-token.nix`](hosts/lab-token.nix); tests use [`tests/lib.nix`](tests/lib.nix)

## Growing to 3-server quorum

1. Bring up bootstrap server0, then agent0.
2. Join server1 and server2 with the same token and `joinUrl`.
3. Confirm three Ready control-plane nodes / etcd members.
4. Practice the replace drill in [docs/etcd-rebuild.md](docs/etcd-rebuild.md).

## Firewall

Ports opened by `modules/common.nix` (firewall stays enabled):

- TCP `6443` (API), `9345` (supervisor), `10250` (kubelet), `9099` (Canal)
- TCP `2379`/`2380` on servers (etcd)
- UDP `8472` (Canal VXLAN)

## Phase 2 (deferred)

Not on the R1–R7 critical path:

- Cilium + `disable-kube-proxy` + HelmChartConfig
- Full airgap module polish beyond `preloadImages`
- Raspberry Pi 4 host profile (`nixos-hardware`)
- `registries.yaml` helper + restart semantics
- deploy-rs / colmena (optional; `nixos-rebuild` covers R7)
- VIP/LB for join URL

## Platform notes

- **CI / containers:** [`scripts/nix-docker.sh`](scripts/nix-docker.sh); [`.github/workflows/ci.yml`](.github/workflows/ci.yml) builds toplevels + qcow2 + ISO.
- **QEMU checks:** Linux + KVM only — not Docker / not GitHub-hosted CI for v1.
- **CNI:** canal. Cilium is Phase 2.
- **Upstream / pins:** OS packages follow flake input `nixpkgs`. RKE2 follows **`nixpkgs-rke2`** — pin-only bump with `nix flake lock --update-input nixpkgs-rke2` (do not float OS `nixpkgs` on every K8s bump). Full OS bump: `nix flake lock --update-input nixpkgs`.

## License

Same as your choice for this repository; RKE2 and nixpkgs retain their upstream licenses.
