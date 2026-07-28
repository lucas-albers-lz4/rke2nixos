## Documentation Polish Plan

### Current state

The rke2nixos docs are in strong shape — well-organized, current, with clear audience targeting and consistent cross-references. All referenced GitHub issues resolve, there are no stale org references, and the TODO.md accurately tracks project status. The main gaps are missing community-entry files (CONTRIBUTING.md, FAQ.md), no automated link checking in CI, and minor cosmetic issues.

### Items

#### Item 1 — CONTRIBUTING.md
**New file** at repo root. Content:
- PR naming conventions (`rke2: ...` for pin-only bumps, `nixpkgs: bump` for OS bumps, `combined:` for emergency bumps)
- Development setup via `nix-docker.sh`
- How to run local builds and QEMU checks (`nix build .#checks.x86_64-linux.*`)
- Review expectations and design-first culture (referencing `docs/design/operating-model-and-upgrades.md`)

#### Item 2 — FAQ.md
**New file** at repo root. Collate hard rules and operator gotchas currently scattered across docs:
- "Never rotate the cluster token after first bootstrap"
- "Never bake the age key into qcow2/ISO images"
- "Generation rollback ≠ etcd/API undo"
- "preloadImages must match the RKE2 binary version"
- "Control-plane needs ≥3072 MiB RAM"
- "Do not use Proxmox default kvm64 CPU"
- "No-wipe-safe: config, packages, sysctl, firewall, RKE2 flags"
- "Not no-wipe-safe: tlsSans, cluster-cidr, service-cidr after first bootstrap"

#### Item 3 — CI: add link checker
**File:** `.github/workflows/ci.yml`
Add a step using `lychee` to check all markdown links on every push/PR:
```yaml
- name: Check markdown links
  run: nix run nixpkgs#lychee -- . --include-fragments --no-ignore -- '.github'
```

#### Item 4 — Fix stale SSH key comment in topology.nix
**File:** `hosts/proxmox/topology.nix`, line 51
Replace `lalbers@lalbers-X470-AORUS-ULTRA-GAMING` with `lalbers@workstation` (or equivalent) in the SSH key comment.

#### Item 5 — Minor dedup: TODO.md / design doc overlap
**File:** `TODO.md`
The lab snapshot table (§ Current lab snapshot in TODO.md) and Phase B status line duplicate content in `docs/design/operating-model-and-upgrades.md`. Have TODO.md say "see design doc §4 for canonical Phase B status" instead of duplicating the Phase B checklist. The lab snapshot stays (it's the operative maintenance view, not a reference for the design doc).

### Acceptance criteria
- [ ] CONTRIBUTING.md exists and covers PR conventions, dev setup, and review expectations
- [ ] FAQ.md exists and covers the 8 hard rules listed above
- [ ] CI pipeline runs `lychee` on all markdown files on every push/PR
- [ ] `topology.nix` has no stale hostname in the SSH key comment
- [ ] TODO.md no longer duplicates Phase B status detail from the design doc
- [ ] All links in CONTRIBUTING.md and FAQ.md resolve
