# Day-2 updates (R7)

Update NixOS configuration on live nodes **without** wiping `/var/lib/rancher/rke2`.

## Tooling

This repo standardizes on **`nixos-rebuild`** via [`scripts/deploy-host.sh`](../scripts/deploy-host.sh).

```bash
export SOPS_AGE_KEY_FILE="$PWD/secrets/age.key"
./scripts/deploy-host.sh proxmox-server0 root@10.0.0.10
./scripts/deploy-host.sh proxmox-agent0 root@10.0.0.11
```

Or locally on the node:

```bash
nixos-rebuild switch --flake /path/to/rke2nixos#proxmox-server0
```

`nix run .#deploy-local -- proxmox-server0` switches the **current** machine.

## When to re-bake vs rebuild-in-place

| Change | Prefer |
|--------|--------|
| Config, packages, sysctl, firewall, RKE2 flags | `deploy-host.sh` / `nixos-rebuild switch` |
| Disk layout, bootloader, first-boot cloud-init | Re-bake qcow2/ISO |
| Cluster token | **Never rotate** after bootstrap — breaks joins |

## Guarantees

- Declarative NixOS closure changes under `/run/current-system`
- Mutable RKE2/etcd/containerd data remains under `/var/lib/rancher/rke2`
- Do not `rm -rf` that directory unless performing a controlled node replace ([etcd-rebuild.md](etcd-rebuild.md))

## Optional later tools

deploy-rs / colmena remain README Phase 2 — not required for day-2 confidence once `nixos-rebuild` works.
