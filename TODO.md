# Next steps (Docker-first → GitHub images)

Bootstrap done: `flake.lock` pinned, `nix flake show` works, `checks.x86_64-linux.server-agent` passed on Linux with KVM.

## Done

### 1. Nix in Docker locally

```bash
./scripts/nix-docker.sh nix flake show
./scripts/nix-docker.sh nix build .#packages.x86_64-linux.example-server0
```

Uses `nixos/nix` with the repo bind-mounted. No host Nix required for eval/build.

### 2. Containerized checks (v1 decision)

- **Docker:** eval and `nix build` of packages/toplevel only.
- **QEMU checks:** host Linux + KVM only (`nix build .#checks.x86_64-linux.server-agent`). Not run in Docker or GitHub-hosted CI until nested virt is proven (`NIX_DOCKER_EXTRA_ARGS='--device /dev/kvm'` as a future experiment).

### 3. Deployable artifacts (toplevel)

Flake packages (closures; ISO/SD/OCI later):

- `.#packages.x86_64-linux.example-server0`
- `.#packages.x86_64-linux.example-agent0`

### 4. GitHub Actions

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) builds those packages on push/PR, caches the Nix store, and uploads artifacts. Does not run RKE2 QEMU checks.

## 5. Later (after CI images work)

- Wire sops-nix: age key in `secrets/.sops.yaml`, encrypt token, replace lab activation-script token on example hosts.
- Smoke interactive VMs (`nix run .#example-server0-vm` / `example-agent0-vm`).
- Disk images (ISO/SD/OCI) beyond toplevel closures.
- Phase 2 backlog stays in README (Cilium, Pi profile, registries helper, deploy tool).
