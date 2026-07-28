# Contributing

Thanks for considering a contribution to rke2nixos! This project follows a **design-first** culture: non-trivial changes start with an issue or design document before code. See the [operating model & design doc](docs/design/operating-model-and-upgrades.md) for the project's architectural principles.

## Quick start

### Prerequisites

- A Linux or macOS workstation with Docker **or** Nix (with `nix-command` and `flakes` enabled)
- For QEMU checks: a Linux host with KVM (`/dev/kvm`, user in `kvm` group)

### Development via Nix-in-Docker (preferred)

```bash
./scripts/nix-docker.sh nix flake show
./scripts/nix-docker.sh nix build .#packages.x86_64-linux.example-server0
./scripts/nix-docker.sh nix build .#packages.x86_64-linux.example-agent0
```

The Docker container includes Nix with flakes pre-configured and builds are isolated from your host.

### Host Nix

```bash
nix flake show

# Build a toplevel
nix build .#packages.x86_64-linux.example-server0

# QEMU checks (Linux + KVM only — not Docker / not GitHub-hosted CI)
nix build .#checks.x86_64-linux.server-agent
nix build .#checks.x86_64-linux.three-server
```

## Pull request conventions

### Title prefixes

| Prefix | When to use | Example |
|--------|-------------|---------|
| `rke2: …` | RKE2 version pin-only bump (`nix flake lock --update-input nixpkgs-rke2`) | `rke2: bump to v1.30.x+rke2r1` |
| `nixpkgs: bump` | OS nixpkgs bump (`nix flake lock --update-input nixpkgs`) | `nixpkgs: bump 2026-07-01` |
| `combined: bump` | Emergency combined bump (both inputs move in one PR) | `combined: bump nixpkgs + rke2 for CVE-2026-xxxx` |
| `feat: …` | New feature or module | `feat: add registries.yaml helper` |
| `fix: …` | Bug fix | `fix: correct VIP failover detection` |
| `docs: …` | Documentation-only change | `docs: add FAQ with hard rules` |
| `refactor: …` | Code restructuring without functional change | `refactor: extract host derivation from flake.nix` |
| `ci: …` | CI-only change | `ci: add lychee link checker` |

### Pin discipline

- **Pin-only PRs** must move only `nixpkgs-rke2` in `flake.lock`, never the OS `nixpkgs` input. CI enforces this via `scripts/check-flake-lock-pins.sh`.
- **OS bump PRs** may also move `nixpkgs-rke2` (the RKE2 pin usually floats with the OS nixpkgs revision).
- **Combined bumps** must be explicitly labeled as such (title prefix `combined:`).

### Before opening a PR

1. Run `nix flake check` (or at minimum `nix build .#packages.x86_64-linux.example-server0#`)
2. For non-trivial changes, reference a corresponding issue or design document
3. For changes that affect the upgrade model, update or reference `docs/design/operating-model-and-upgrades.md`
4. Ensure all markdown links resolve (CI will check this)

## Design-first culture

Substantial changes follow this process:

1. **Issue** — discuss the problem or gap
2. **Design document** (if needed) — draft operating principles and approach in `docs/design/`
3. **Multi-model review** (for major changes) — validate the design via MCR before implementing
4. **Implementation** — code changes + docs + tests
5. **Live proof** — exercised on the reference Proxmox fleet before merging (P8 principle)

This ensures the project's principles (P1–P9 in the operating model doc) are respected and documented trade-offs are explicit.

## Code review expectations

- All PRs must have at least one approving review from a maintainer
- Design changes that affect principles should reference which principles they touch
- No hard-coded secrets or credentials — use sops-nix and age keys
- No binaries committed to the repository
- Commit messages should be descriptive and reference issues where applicable

## Testing

### Local checks

```bash
# Flake evaluation
nix flake check  # runs formatter + builds all checks

# Individual test suites
nix build .#checks.x86_64-linux.single-node
nix build .#checks.x86_64-linux.server-agent    # multi-node join (requires KVM)
nix build .#checks.x86_64-linux.three-server    # 3 CP HA test (requires KVM)
```

### CI checks

Every push and pull request runs:

- `scripts/check-flake-lock-pins.sh` — enforces pin discipline
- `nix flake show` — validates flake evaluation
- Build `example-server0` and `example-agent0` toplevels
- Build `proxmox-server0-qcow2` and `installer-iso`
- `lychee` markdown link check (on all `.md` files)

Full QEMU `nixosTest` suites run locally but are not executed in GitHub-hosted CI (they require KVM).

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
