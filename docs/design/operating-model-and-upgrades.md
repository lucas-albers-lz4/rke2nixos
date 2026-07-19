# Operating model & day-2 architecture

**Status:** Draft for architect review  
**Audience:** Maintainers and external reviewers (NixOS, Kubernetes, platform)  
**Related:** [../TODO.md](../TODO.md), [../day2-updates.md](../day2-updates.md), [../etcd-rebuild.md](../etcd-rebuild.md), [../README.md](../README.md)  
**Non-goal of this doc:** Implement VIP, Cilium, or HA live bring-up — those are downstream workstreams constrained by the principles below.

---

## 1. Purpose

This document states the **guidelines that drive architectural decisions** for rke2nixos, then proposes a concrete **operating and upgrade model** consistent with those guidelines. It exists so reviewers can:

- Challenge the principles if they disagree with the product identity
- Improve the approach without re-litigating “should this be Talos?”
- Add risks, alternatives, and success criteria productively

If a proposed feature violates a principle, the burden is to **change the principle explicitly** (and accept the trade-offs), not to quietly bolt on an incompatible mechanism.

---

## 2. Product identity (one paragraph)

**rke2nixos** is a flake-shaped way to run RKE2 where **NixOS is the source of truth for the machine** (OS, packages, unit config, firewall, sysctl, secrets wiring) and **RKE2 owns mutable cluster state** under `/var/lib/rancher/rke2`. We optimize for **reproducibility, auditability, and fixed or slowly changing topologies** (homelab, edge, bare metal, small Proxmox fleets)—not for cloud autoscaling pools or “K8s channel” UX that bypasses Nix.

---

## 3. Guiding principles

These are normative. Numbered for reference in reviews (“conflicts with P3”).

### P1 — One evaluated system of record

A node’s intended state is a **NixOS configuration** in this flake (plus encrypted secrets). Host packages, RKE2 service config, and supporting agents are not installed by ad-hoc scripts on a writable root.

**Implication:** Day-2 changes go through flake evaluation → build/copy → activate (or re-bake). Side channels that install RKE2 tarballs onto the node are out of scope unless promoted to a new, explicit principle.

### P2 — Immutable OS, mutable cluster data

- **Immutable / declarative:** Nix store, generation, most of `/etc` as managed by NixOS.  
- **Mutable by design:** `/var/lib/rancher/rke2` (etcd, containerd content, certs, agent state).

**Implication:** NixOS generation rollback restores OS + packaged RKE2 *binaries/units/config*. It does **not** rewind etcd or guarantee API compatibility undo. Runbooks must say this out loud.

### P3 — Reproducibility over familiar distro UX

When forced to choose between “feels like Ubuntu/Talos channels” and “bit-identical, reviewable closures,” we choose the latter. We may add **thin CLIs or docs** that *narrow* Nix workflows; we do not fake a second package manager for Kubernetes.

### P4 — Pin independence, not lifecycle independence

Kubernetes version may be an **independent decision** (dedicated flake input / overlay pin, dedicated PR, dedicated CI job). It is **not** an independent *install path*. Operators still apply a Nix generation (live deploy or baked image).

### P5 — Fixed topology first; templates second; autoscaling last

- **First-class:** Named hosts (or a small generated set) with sticky join targets.  
- **Welcome:** Shared modules + parameterized host lists to reduce boilerplate.  
- **Deferred:** ASG-style “spawn N identical workers from a machine config API” (Talos-like). That is a different product class.

### P6 — Prefer boring Kubernetes operations on top of Nix

Drain/cordon, etcd member replace, sticky registration address / VIP, and upgrade *ordering* are ordinary cluster ops. Nix does not replace them. Where industry tools help **ordering** (e.g. plans that drain nodes), they may orchestrate **which node applies the next generation**—they must not become a source of truth for node contents.

### P7 — Secrets are declarative; keys are not baked into images

Cluster token and similar secrets live in sops-encrypted files in git. Age private keys are delivered at first boot (cloud-init / cidata / documented inject)—**never** into published qcow2/ISO artifacts.

### P8 — Prove on a runway before expanding surface area

Live confidence order matters more than feature breadth: 1+1 Ready → day-2 no-wipe → 3 CP + etcd drill → then Phase 2 (Cilium, VIP-as-product, Pi, etc.). Scaffolding without live proof stays labeled scaffolding.

### P9 — Explicit non-goals (for this phase of the project)

- Matching Talos’s “no SSH, API-only” posture as a requirement (we use SSH for day-2 and break-glass).  
- Decoupling RKE2 upgrades from Nix activation while keeping Nix as SoT.  
- Competing with managed Rancher UX for channel subscriptions.  
- Dynamic node pools / cluster autoscaler–driven machine creation.

---

## 4. Problem statement (why this doc exists)

External comparisons correctly note that **day-2 Kubernetes upgrades feel coupled to the OS**. That coupling is real. Misreading it leads to bad designs:

| Misread | Bad response |
|--------|----------------|
| “Nix can’t do K8s upgrades cleanly” | Install upstream RKE2 outside Nix |
| “We need Talos UX” | Parallel upgrade stacks, drift |
| “Generation rollback fixes bad upgrades” | Assume etcd/API undo |

We need a stated model that:

1. Keeps P1–P4 intact  
2. Makes version bumps **narrow, reviewable, and operable**  
3. Separates **OS rollback** from **cluster data plane risk**  
4. Aligns other gaps (join URL, HA, secrets, scaling) with the same principles  

---

## 5. Current architecture (as-built)

```text
                    ┌─────────────────────────────────────┐
   flake.nix        │  nixosConfigurations.*              │
   hosts/*          │  modules/rke2nixos + profiles       │
   secrets/*.enc    │  sops-nix → /run/secrets            │
                    └──────────────┬──────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
        baked qcow2/ISO      deploy-host.sh        QEMU nixosTest
        (Proxmox/metal)      nixos-rebuild         (CI topology)
              │                    │
              ▼                    ▼
        ┌─────────────────────────────────────────────┐
        │ NixOS generation (immutable closure)         │
        │  - rke2 package + units + config             │
        │  - firewall, sysctl, agents, SSH keys        │
        └─────────────────────┬───────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │ /var/lib/rancher/rke2  (mutable cluster)     │
        │  etcd, containerd, certs, charts, agent data │
        └─────────────────────────────────────────────┘
```

**Join model today:** sticky `bootstrapHost` (often an IP) in `hosts/proxmox/settings.nix`; agents/joining servers use `joinUrl` + shared token; `networking.extraHosts` maps IP→`server0` when needed. VIP/LB is Phase 2.

**Delivery today:** Proxmox import + age cidata ISO; live `scripts/deploy-host.sh`; least-privilege API token + node `rke2ops` for `qm guest` IP discovery.

---

## 6. Proposed day-2 & upgrade model

### 6.1 Mental model we teach

```text
┌──────────────────────────┐     ┌──────────────────────────────┐
│ Decision: K8s / RKE2 ver │     │ Decision: OS / nixpkgs bump  │
│ (narrow flake input pin) │     │ (broader, slower cadence)    │
└────────────┬─────────────┘     └──────────────┬───────────────┘
             │                                    │
             └────────────────┬───────────────────┘
                              ▼
                   Evaluate flake → build closure
                              ▼
              Apply via rolling deploy OR re-bake images
                              ▼
                   Cluster ops: drain / order / verify
```

- **Two decisions**, still **one apply mechanism** (Nix generation).  
- Cadence may differ (K8s pins more often than full nixpkgs floats).  
- CI should be able to test “pin-only” bumps without requiring unrelated package churn when locks allow.

### 6.2 Version pinning (policy independence)

**Proposed convention (to implement):**

1. Single documented place for the RKE2 version pin (flake input and/or overlay)—exact file layout TBD in implementation PR; reviewers should insist it remains **one** place.  
2. PRs titled clearly: `rke2: vX.Y.Z` vs `nixpkgs: bump` vs `hosts: …`.  
3. CI path that builds at least one server+agent closure (and preferably an existing nixosTest) on pin bumps.  
4. Changelog / runbook note: which skew is supported (RKE2’s own upgrade skew rules still apply).

This delivers **pin independence** without a second install path.

### 6.3 Apply paths (unchanged product, clearer roles)

| Path | When | Notes |
|------|------|--------|
| `scripts/deploy-host.sh` | Live lab / day-2 config and pin bumps | Leaves `/var/lib/rancher/rke2` intact |
| Re-bake qcow2/ISO + replace disk | Disk/boot/first-boot/cloud-init class changes | Heavier; not default for vim-level day-2 |
| NixOS generation rollback | Bad *OS/config* activation | Does not undo etcd migrations |

### 6.4 Rolling order (cluster ops on top of Nix)

For control-plane pin bumps:

1. Verify backup / etcd health on bootstrap (or quorum).  
2. Upgrade **one** non-last CP first when HA exists; wait Ready.  
3. Remaining CPs; then agents.  
4. For single-CP labs: accept maintenance window; document risk.

Automation may grow from a scripted runbook → optional plan controller that only sequences **which node runs deploy**. Content remains the flake.

### 6.5 What we refuse (anti-design)

- Installing RKE2 from upstream tarballs alongside NixOS “for easier upgrades.”  
- Claiming “rollback generation = safe K8s downgrade.”  
- Floating `nixpkgs` on every K8s bump without calling out blast radius.  
- Autoscaling APIs as a substitute for host entries in the flake (until P5 is formally revised).

### 6.6 Optional thin UX (cosmetic, principle-compliant)

A future `scripts/upgrade-rke2.sh` (name TBD) that:

1. Bumps only the RKE2 pin  
2. Runs CI-equivalent build  
3. Invokes rolling `deploy-host.sh` per inventory  

Under the hood it remains Nix. The win is **operator focus**, not a new truth source.

---

## 7. How principles apply to other known gaps

Reviewers can use this table to check consistency of future proposals.

| Gap | Severity (ops) | Approach consistent with principles | Anti-pattern |
|-----|----------------|-------------------------------------|--------------|
| Sticky join / dual DHCP IPs | High | Static addressing or DHCP reservations; later VIP/LB as Phase 2 **still declared in flake** (P1, P5) | Ad-hoc `/etc/hosts` as permanent SoT |
| Live HA + etcd drill | High | Execute R6 per [etcd-rebuild.md](../etcd-rebuild.md); keep join URL sticky until VIP (P8) | Hope single CP + backups suffice undocumented |
| Age / first-boot secrets | High | Keep cidata/cloud-init delivery; never bake age key into images (P7) | Commit keys; empty placeholder files |
| CP memory floor (~≥3 GiB) | Medium | Import defaults + docs; fail loud under 2 GiB | Silent OOM loops |
| Node boilerplate / scale-out | Medium | Shared modules + host list generation (P5 templates) | Copy-paste hosts with drift |
| Build times | Medium | Binary caches, pin-only bumps, baked images for cold start | Disable purity / impure host installs |
| Cilium / advanced CNI | Lower (Phase 2) | Package/module + rebuild/reboot as needed (P2) | Drop binaries into `/opt` outside Nix |
| “Talos-like channel UX” | Product | Thin wrapper + pin discipline (P3, P4) | Out-of-band RKE2 |

---

## 8. Phased workplan (engineering, not a second product)

Phases are ordered by dependency and P8 (prove runway).

### Phase A — Document & pin discipline (near-term)

- Land this design; iterate from architect review.  
- Document RKE2 pin location and “pin-only vs nixpkgs bump” PR norms.  
- Extend day-2 docs with upgrade skew + rollback honesty (P2).  
- Capture sticky IP / DHCP reservation requirements next to `bootstrapHost`.

### Phase B — Operability helpers

- Inventory-aware rolling deploy helper (CP then agents).  
- Optional `upgrade-rke2` thin CLI (P4 + cosmetic UX).  
- CI job focused on RKE2 pin bumps.  
- Harden age cidata path / first-boot activate (already partially done).

### Phase C — Live HA (checklist item 3)

- Bake/import server1/server2; join to sticky bootstrap; 3 Ready CPs.  
- Practice etcd member replace once ([etcd-rebuild.md](../etcd-rebuild.md)).  
- Resolve RAM layout (keep agent vs L12 split vs pause agent)—environment decision, not principle change.

### Phase D — Phase 2 features (explicitly later)

- VIP/LB for join URL (still flake-declared).  
- Cilium + kernel requirements.  
- aarch64/Pi hardware profiles.  
- Richer host generation from a node list.

Each phase should cite principles it relies on; proposals that need new principles update **§3** first.

---

## 9. Comparison frame (for external architects)

| Concern | rke2nixos stance | Talos-like | Ubuntu + Ansible + RKE2 |
|--------|------------------|------------|-------------------------|
| Node SoT | Nix flake | Machine config API | Ansible + packages |
| K8s version bump | Pin + generation apply | Channel / k8s upgrade API | Package/channel + ansible |
| OS rollback | Generations | Image A/B style | Snapshots/reimage |
| Etcd undo | Not implied by OS rollback | Not magic either | Not magic either |
| Dynamic pools | Non-goal (P5/P9) | Strength | Strength (cloud) |
| Audit / bit identity | Strength (P3) | Strong images | Drift risk |
| Learning curve | Nix (accepted) | Lower YAML | Moderate |

We are not trying to win the Talos column. We are trying to be the best **Nix-native RKE2** option with honest day-2 semantics.

---

## 10. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Operators treat generation rollback as K8s downgrade | Docs + deploy script warnings; upgrade runbook |
| Pin bumps secretly float nixpkgs | CI diff / lockfile review norms; separate PR types |
| Thin upgrade CLI becomes impure SoT | CLI only edits flake inputs + calls existing deploy |
| HA delayed → production on 1 CP | TODO checklist; refuse “prod” claims until Phase C |
| Sticky IP chaos | Reservations/static; qm guest discovery; VIP later |

---

## 11. Success criteria

**Design accepted when reviewers can answer yes:**

1. Principles P1–P9 are clear enough to accept or amend.  
2. Upgrade model (pin independence + Nix apply) is understood as intentional.  
3. Anti-designs in §6.5 are agreed or explicitly replaced.  
4. Phases A–D are a sane backlog order relative to [TODO.md](../TODO.md).

**Implementation (later) succeeds when:**

1. A documented pin-only RKE2 bump is exercised live via `deploy-host.sh` without wiping RKE2 state.  
2. Rollback messaging is visible in day-2 docs.  
3. Live R6 (Phase C) closes checklist item 3.  
4. No merged feature relies on out-of-band RKE2 installs.

---

## 12. Open questions for review

Please comment with principle IDs where possible.

1. **Pin shape:** Prefer a dedicated flake input for `rke2` vs tracking nixpkgs and documenting the attribute path only?  
2. **Rolling automation:** Scripted inventory enough for v1, or invest early in upgrade plans (SUC-style) that only sequence deploys?  
3. **Single-CP labs:** Hard-require HA before calling a cluster “durable,” or allow documented single-CP with backups?  
4. **VIP timing:** Keep Phase D, or promote sticky-VIP ahead of Cilium because join URL pain is already live?  
5. **Host generation:** Is a `nodes.nix` list → generated `nixosConfigurations` acceptable under P5, or keep fully hand-written hosts until after HA?  
6. **SSH posture:** Confirm break-glass SSH remains first-class (unlike Talos), including for `deploy-host.sh`.

---

## 13. Revision history

| Date | Change |
|------|--------|
| 2026-07-19 | Initial draft for architect review (operating principles + upgrade model) |
