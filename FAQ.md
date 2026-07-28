# Frequently asked questions

## Cluster token

### Can I rotate the cluster token after bootstrap?

**No.** The token is shared by all nodes at join time; regenerating it breaks joins and rebuilds. Generate it once via `./scripts/sops-bootstrap.sh`, store it in `secrets/rke2-token.enc.yaml`, and reuse forever.

If you believe the token is compromised, the recovery path is a controlled cluster rebuild — not an in-place rotation.

## Secrets & keys

### Can I bake the age key into the qcow2 or ISO?

**Never.** The age private key (`secrets/age.key`) must be delivered at first boot via cloud-init/cidata (see `scripts/proxmox-age-cloudinit.sh`) or manually injected as `/var/lib/sops-nix/key.txt`. Baking the key into published artifacts violates P7 and would expose cluster secrets to anyone who downloads the image.

### What if I lose `secrets/age.key`?

Run `./scripts/sops-bootstrap.sh` to generate a fresh key pair, then update `.sops.yaml` with the new public key and re-encrypt the secrets. Existing nodes continue working with their old key; new nodes use the new key.

## Upgrades & rollbacks

### Does NixOS generation rollback undo a bad upgrade?

**Not fully.** Generation rollback restores the OS, packaged RKE2 binaries, systemd units, and config. It does **not** rewind:
- etcd data
- containerd content store
- CNI plugin binaries cached under `/var/lib/rancher/rke2`
- Helm chart state

If a control-plane does not return Ready after a deploy, stop the roll and run `nixos-rebuild switch --rollback` on that node before continuing.

### Can I change `tlsSans`, `cluster-cidr`, or `service-cidr` after first bootstrap?

**Not as a no-wipe change.** API server certificates are generated at first start under `/var/lib/rancher/rke2/server/tls`; `--tls-san` changes do not auto-regenerate. CIDR changes generally require a controlled rebuild. See `docs/day2-updates.md` for what is and isn't no-wipe-safe.

### What changes are safe to apply via `deploy-host.sh`?

| Safe (no-wipe) | Not safe (needs re-bake or controlled rebuild) |
|----------------|-----------------------------------------------|
| Config, packages, sysctl, firewall, RKE2 flags | Disk layout, bootloader, first-boot cloud-init |
| SSH key changes | `tlsSans`, cluster-cidr, service-cidr |
| RKE2 pin bump (via `nixpkgs-rke2`) | Cluster token rotation |

## Hardware & Proxmox

### Why does my control-plane stay NotReady?

The most common cause is insufficient RAM. Control-plane resource requests alone are ~1.8 GiB. At the Proxmox import default of 2 GiB, the node often stays NotReady. Use **≥3072 MiB** for control planes:

```bash
PROXMOX_MEMORY=3072 ./scripts/proxmox-import.sh ...
```

### Why do I need `cpu=host`?

RKE2 images use glibc that requires x86-64-v2. The Proxmox default `kvm64` CPU type does not satisfy this. The import script (`scripts/proxmox-import.sh`) sets `cpu=host` automatically — do not override it.

### Can I reuse a VM disk that already joined the cluster?

**No.** A disk that previously joined under a different hostname has stale agent identity. Destroy/reclone the VM, or wipe `/var/lib/rancher/rke2` and `/etc/rancher/node` after the Kubernetes node object is removed.

## Golden agents

### What's the difference between a named host and a golden agent?

**Named hosts** (e.g. `proxmox-server0`, `proxmox-agent0`) get their full identity (hostname, IP, token, SSH keys) from the Nix configuration — the flake is the source of truth.

**Golden agents** are a single qcow2 template that receives per-clone identity at first boot via cloud-init/cidata (hostname, IP, join URL). They are stateless workers only. See `docs/golden-agent.md`.

## `preloadImages`

### Do I need `preloadImages = true`?

Only for QEMU tests and airgap deployments. Live Proxmox hosts in this repo use `preloadImages = false`. When enabled, the image tarballs must match the RKE2 binary from the same package — after an RKE2 pin-only bump, rebuild and redeploy so staged archives come from the new package.

## General

### Can I use deploy-rs or Colmena?

These are Phase 2 (optional). `nixos-rebuild` via `scripts/deploy-host.sh` is sufficient for day-2 confidence. See issue [#5](https://github.com/lucas-albers-lz4/rke2nixos/issues/5).

### Can I join the cluster without a VIP?

Yes, as a break-glass option. The `bootstrapHost` (bootstrap control-plane static IP) is the fallback join URL. This is not considered durable for HA — see the bootstrap-failure runbook in the [operating model doc](docs/design/operating-model-and-upgrades.md#bootstrap-host-failure-runbook-interim-until-vip).

### Does rke2nixos support aarch64 / Raspberry Pi?

The flake includes `aarch64-linux` packages and NixOS configurations (`example-server0-aarch64`, `example-agent0-aarch64`), but Raspberry Pi host profiles (`nixos-hardware`) are Phase D — not yet on the critical path.
