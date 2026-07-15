# Next steps (Docker-first → GitHub images)

Bootstrap done: `flake.lock` pinned, `nix flake show` works, `checks.x86_64-linux.server-agent` passed on Linux with KVM.

## 1. Nix in Docker locally

Run a standard image (e.g. `nixos/nix`) with flakes enabled, bind-mount this repo, and inside the container:

```bash
nix flake show
nix build .#nixosConfigurations.example-server0.config.system.build.toplevel
```

Goal: day-to-day Nix without relying on a host Nix install.

## 2. Containerized checks

Decide how far VM tests go in Docker:

- With KVM: pass `--device /dev/kvm` and re-run `.#checks.x86_64-linux.server-agent` (and later `single-node` / `three-server`).
- Without KVM: keep heavy QEMU checks on a Linux runner with KVM; use the container for eval/`nix build` only.

## 3. Build deployable artifacts in-container

Define flake outputs for images we ship (NixOS system closure / SD or ISO / OCI as appropriate for RKE2 hosts). Build them with `nix build` inside Docker so the recipe matches CI.

## 4. GitHub Actions

Add a workflow that uses the same Docker/Nix (or Determinate / nix-installer) path to build those image outputs on push/PR; cache the Nix store; upload artifacts.

## 5. Later (after CI images work)

- Wire sops-nix: age key in `secrets/.sops.yaml`, encrypt token, replace lab activation-script token on example hosts.
- Smoke interactive VMs (`nix run .#example-server0-vm` / `example-agent0-vm`).
- Phase 2 backlog stays in README (Cilium, Pi profile, registries helper, deploy tool).
