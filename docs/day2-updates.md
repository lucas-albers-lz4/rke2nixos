# Day-2 updates (R7)

Update NixOS configuration on live nodes **without** wiping `/var/lib/rancher/rke2`.

Canonical upgrade philosophy: [design/operating-model-and-upgrades.md](design/operating-model-and-upgrades.md).

## Tooling

This repo standardizes on **`nixos-rebuild`** via [`scripts/deploy-host.sh`](../scripts/deploy-host.sh).

```bash
export SOPS_AGE_KEY_FILE="$PWD/secrets/age.key"
./scripts/deploy-host.sh proxmox-server0 root@192.168.1.32
./scripts/deploy-host.sh proxmox-agent0 root@192.168.1.25
```

Targets match [`hosts/proxmox/inventory.nix`](../hosts/proxmox/inventory.nix) (derived from [`topology.nix`](../hosts/proxmox/topology.nix)).

`deploy-host.sh` uses `nixos-rebuild` when available, otherwise `nix shell nixpkgs#nixos-rebuild -c nixos-rebuild` (common when only the nix CLI is installed).

Or locally on the node:

```bash
nixos-rebuild switch --flake /path/to/rke2nixos#proxmox-server0
```

`nix run .#deploy-local -- proxmox-server0` switches the **current** machine.

`deploy-host.sh` is a **single-host** apply tool. Rolling upgrade order (cordon/drain/wait Ready) is a separate Phase B helper — see the design doc §6.4.

## When to re-bake vs rebuild-in-place

| Change | Prefer |
|--------|--------|
| Config, packages, sysctl, firewall, RKE2 flags | `deploy-host.sh` / `nixos-rebuild switch` |
| Disk layout, bootloader, first-boot cloud-init | Re-bake qcow2/ISO |
| Cluster token | **Never rotate** after bootstrap — breaks joins |
| `tlsSans`, cluster-cidr, service-cidr after first bootstrap | **Not no-wipe-safe** — needs cert rotation or controlled rebuild (design §6.3) |

## Guarantees

- Declarative NixOS closure changes under `/run/current-system`
- Mutable RKE2/etcd/containerd data remains under `/var/lib/rancher/rke2`
- Do not `rm -rf` that directory unless performing a controlled node replace ([etcd-rebuild.md](etcd-rebuild.md))

## Rollback honesty

NixOS generation rollback restores OS + packaged RKE2 binaries/units/config. It does **not** rewind etcd, the containerd content store, CNI plugin binaries cached under `/var/lib/rancher/rke2`, or Helm chart state. If a control-plane does not return Ready after a deploy, stop the roll and consider `nixos-rebuild switch --rollback` on that node before continuing.

## preloadImages and pin bumps

`rke2nixos.preloadImages = true` stages RKE2 version-bound image archives from `rke2nixos.package` into `/var/lib/rancher/rke2/agent/images` (used by QEMU tests / airgap). Live Proxmox hosts in this repo use `preloadImages = false`.

When preload is enabled, image tarballs must match the RKE2 binary from the same package. After an RKE2 pin-only bump, rebuild/redeploy so staged archives come from the new package — do not leave old tarballs paired with a new binary.

## Pin bumps

RKE2 is pinned by flake input `nixpkgs-rke2`:

```bash
nix flake lock --update-input nixpkgs-rke2
# build + rolling deploy per design §6.2 / §6.4
```

Do not float OS `nixpkgs` on a pin-only PR. Respect RKE2’s own upgrade skew rules (kubelet must not be newer than kube-apiserver).

## Optional later tools

deploy-rs / colmena remain README Phase 2 — not required for day-2 confidence once `nixos-rebuild` works.
