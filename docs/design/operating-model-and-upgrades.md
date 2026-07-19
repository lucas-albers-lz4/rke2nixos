# Operating model & day-2 architecture

**Status:** Draft revised after multi-model review ([issue #1](https://github.com/lucas-albers-lz4/rke2nixos/issues/1))  
**Audience:** Maintainers and external reviewers (NixOS, Kubernetes, platform)  
**Related:** [../TODO.md](../TODO.md), [../day2-updates.md](../day2-updates.md), [../etcd-rebuild.md](../etcd-rebuild.md), [../README.md](../README.md)  
**Non-goal of this doc:** Implement VIP, Cilium, or HA live bring-up in *this* revision — those are downstream workstreams constrained by the principles below. Pin shape is **decided here**; the `nixpkgs-rke2` input lands in a follow-on implementation PR.

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

Multiple flake inputs (e.g. OS `nixpkgs` and `nixpkgs-rke2`) are fine under P1: they must be **evaluated together** and applied through **one NixOS generation**. “One system of record” means one activation path, not one lockfile node.

**Implication:** Day-2 changes go through flake evaluation → build/copy → activate (or re-bake). Side channels that install RKE2 tarballs onto the node are out of scope unless promoted to a new, explicit principle.

### P2 — Immutable OS, mutable cluster data

- **Immutable / declarative:** Nix store, generation, most of `/etc` as managed by NixOS.  
- **Mutable by design:** `/var/lib/rancher/rke2` (etcd, containerd content, certs, agent state, CNI plugin binaries cached there, Helm chart state).

**Implication:** NixOS generation rollback restores OS + packaged RKE2 *binaries/units/config*. It does **not** rewind etcd, the containerd content store, CNI plugin binaries under `/var/lib/rancher/rke2`, or Helm chart state, and does not guarantee API compatibility undo. Runbooks must say this out loud.

### P3 — Reproducibility over familiar distro UX

When forced to choose between “feels like Ubuntu/Talos channels” and “bit-identical, reviewable closures,” we choose the latter. We may add **thin CLIs or docs** that *narrow* Nix workflows; we do not fake a second package manager for Kubernetes.

**Thin-CLI guardrail test:** A thin CLI must (1) only mutate the flake or call existing flake-derived scripts, (2) not own cluster state, (3) not have its own config file outside the flake, and (4) be removable without loss of functionality. Reviewers should reject PRs that fail this test.

### P4 — Pin independence, not lifecycle independence

Kubernetes version may be an **independent decision** (dedicated `nixpkgs-rke2` flake input, dedicated PR, dedicated CI checks). It is **not** an independent *install path*. Operators still apply a Nix generation (live deploy or baked image).

### P5 — Fixed topology first; templates second; autoscaling last

- **First-class:** Named hosts (or a small generated set) with sticky join targets.  
- **Welcome:** Shared modules + parameterized host lists to reduce boilerplate.  
- **Deferred:** ASG-style “spawn N identical workers from a machine config API” (Talos-like). That is a different product class.

### P6 — Prefer boring Kubernetes operations on top of Nix

Drain/cordon, etcd member replace, sticky registration address / VIP, and upgrade *ordering* are ordinary cluster ops. Nix does not replace them. Where industry tools help **ordering** (e.g. plans that drain nodes), they may orchestrate **which node applies the next generation**—they must not become a source of truth for node contents.

### P7 — Secrets wiring is declarative; keys are not baked into images

Secrets **wiring** (sops-nix paths, tokenFile, unit dependencies) is declarative. Secret **values** live in encrypted files in git as opaque blobs. Age private keys are delivered at first boot (cloud-init / cidata / documented inject)—**never** into published qcow2/ISO artifacts.

### P8 — Prove on a runway before expanding surface area

Live confidence order matters more than feature breadth: 1+1 Ready → day-2 no-wipe → 3 CP + etcd drill → then Phase 2 (Cilium, Pi, etc.). Scaffolding without live proof stays labeled scaffolding.

**Status note:** Proxmox 1+1 Ready and day-2 no-wipe are live. Live R6 (3 CP + etcd drill) is **paused** — host configs and QEMU checks exist as scaffolding only (see [TODO.md](../TODO.md)).

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
        (Proxmox/metal)      nixos-rebuild         (local / KVM)
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

**Join model today:** sticky `bootstrapHost` (often an IP) in `hosts/proxmox/settings.nix`; agents/joining servers use `joinUrl` + shared token; `networking.extraHosts` maps IP→`server0` when needed. VIP/LB is promoted to Phase B (not yet implemented)—see §7 and §8.

**Delivery today:** Proxmox import + age cidata ISO; live `scripts/deploy-host.sh`; least-privilege API token + node `rke2ops` for `qm guest` IP discovery.

**Pin status today:** RKE2 resolves via `pkgs.rke2` from the single OS `nixpkgs` input. The `nixpkgs-rke2` input (§6.2) is **as-designed**; it is not yet in `flake.nix`. Until the implementation PR lands, a `nix flake update` still floats RKE2 with the OS.

---

## 6. Day-2 & upgrade model

### 6.1 Mental model we teach (as-designed)

```text
┌──────────────────────────┐     ┌──────────────────────────────┐
│ Decision: K8s / RKE2 ver │     │ Decision: OS / nixpkgs bump  │
│ (nixpkgs-rke2 input)     │     │ (broader, slower cadence)    │
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
- Label flips to **as-implemented** once `nixpkgs-rke2` is wired and a pin-only bump is exercised.

### 6.2 Version pinning (policy independence)

**Decided convention (single place — the flake input):**

1. **Pin location:** flake input `nixpkgs-rke2` — a nixpkgs revision that carries the desired RKE2 package. Default `rke2nixos.package` is wired from that input (via existing `rke2nixos.package` in `modules/cluster-defaults.nix`). No separate `pins.nix` for v1; attr-only selection within the OS nixpkgs cannot deliver true pin independence when the desired RKE2 is newer than OS nixpkgs.  
2. **Pin-only bump:** `nix flake lock --update-input nixpkgs-rke2` (or equivalent lock edit). PRs titled `rke2: …` must not move the OS `nixpkgs` lock node.  
3. **OS bump:** `nix flake lock --update-input nixpkgs` (and usually `sops-nix`); may also move `nixpkgs-rke2` when doing a combined emergency bump (§10). PRs titled `nixpkgs: bump`.  
4. **CI (v1, GitHub-hosted):** `nix flake show` + build at least one server and one agent **toplevel** (already in `.github/workflows/ci.yml`). On PRs that change `flake.lock`, fail if both `nixpkgs` and `nixpkgs-rke2` moved unless the PR is explicitly a combined bump. Full QEMU `nixosTest` (`three-server`, etc.) stays **local / Linux+KVM only** — not GitHub-hosted for v1.  
5. **Skew:** RKE2’s own upgrade skew rules still apply (kubelet must not be newer than kube-apiserver; follow upstream RKE2 upgrade docs for the release pair). Document the supported skew in the changelog/runbook note for each pin bump.

This delivers **pin independence** without a second install path. Until the input lands, treat P4 as decided but not yet a property of the tree.

### 6.3 Apply paths (unchanged product, clearer roles)

| Path | When (examples) | Reboot expected? | Notes |
|------|-----------------|------------------|--------|
| `scripts/deploy-host.sh` | Pin bump; firewall/sysctl tweak; SSH key add; RKE2 flag change that RKE2 reloads | Usually **no** for RKE2-only; **yes** if kernel/systemd/initrd change | Leaves `/var/lib/rancher/rke2` intact. Single-host tool — not a rolling orchestrator. |
| Re-bake qcow2/ISO + replace disk | Disk layout, bootloader, first-boot cloud-init / age cidata class changes | Yes (new disk / first boot) | Heavier; not default for vim-level day-2 |
| NixOS generation rollback | Bad *OS/config* activation (e.g. broken unit after deploy) | Sometimes | Does **not** undo etcd migrations, containerd content, or CNI/Helm state under `/var/lib/rancher/rke2` |
| Manual cert rotation / re-bootstrap | Changing `tlsSans`, cluster-cidr, or service-cidr after first bootstrap | Often | **Not no-wipe-safe.** API server certs are generated at first start under `/var/lib/rancher/rke2/server/tls`; `--tls-san` changes do not auto-regenerate. CIDR changes generally require controlled rebuild. |

### 6.4 Rolling order (cluster ops on top of Nix)

`deploy-host.sh` applies **one** host. Rolling safety is a separate concern (Phase B `rolling-upgrade.sh`).

For control-plane pin bumps:

1. Verify etcd backup exists and etcd/API health on bootstrap (or quorum). v1: manual snapshot per [etcd-rebuild.md](../etcd-rebuild.md); automated snapshot cron is later.  
2. Upgrade **one** non-last CP first when HA exists; wait Node Ready + etcd healthy.  
3. Remaining CPs (respect RKE2 skew — do not advance kubelets ahead of apiservers); then agents.  
4. For single-CP labs: accept a maintenance window; document risk; do not call the cluster production-durable.

**Failure during rolling upgrade:** If a control-plane does not return Ready within a bounded window (operator-chosen; e.g. 10–15 minutes), stop the roll. On that node, roll back the OS generation (`nixos-rebuild switch --rollback` or equivalent), re-check node/etcd health, then decide whether to drain/re-image or fix-forward. Generation rollback does not rewind etcd (P2).

Automation for v1: scripted inventory that sequences which node runs `deploy-host.sh` (cordon → drain → deploy → wait Ready → uncordon). No SUC-style plan controller yet. Inventory must be flake-derived (e.g. evaluated node list), not a sibling YAML that becomes a second SoT.

### 6.5 What we refuse (anti-design)

- Installing RKE2 from upstream tarballs alongside NixOS “for easier upgrades.”  
- Claiming “rollback generation = safe K8s downgrade.”  
- Floating OS `nixpkgs` on every K8s bump without calling out blast radius (CI should catch accidental dual-lock moves on `rke2:` PRs).  
- Autoscaling APIs as a substitute for host entries in the flake (until P5 is formally revised).  
- Thin CLIs that own cluster state or config outside the flake (P3 guardrail).

### 6.6 Optional thin UX (cosmetic, principle-compliant)

A future `scripts/upgrade-rke2.sh` (name TBD) that:

1. Bumps only the RKE2 pin via `nix flake lock --update-input nixpkgs-rke2` (§6.2)  
2. Runs CI-equivalent toplevel builds  
3. Invokes rolling deploy per flake-derived inventory  

Must pass the P3 thin-CLI guardrail test. Under the hood it remains Nix. The win is **operator focus**, not a new truth source.

---

## 7. How principles apply to other known gaps

Reviewers can use this table to check consistency of future proposals. **Severity** = operational impact if unmitigated while claiming a durable cluster.

| Gap | Severity | Approach consistent with principles | Anti-pattern |
|-----|----------|-------------------------------------|--------------|
| Sticky join / dual DHCP IPs | High | DHCP reservation or static IP matching `bootstrapHost`; bootstrap-failure runbook (§10); VIP/LB in **Phase B** still declared in flake (P1, P5). **No production claim** while join URL is a single sticky host. | Ad-hoc `/etc/hosts` as permanent SoT; shipping 3-CP as “HA join” without VIP or runbook |
| Live HA + etcd drill | High | Execute live R6 when runway resumes ([etcd-rebuild.md](../etcd-rebuild.md)); scaffolding already present (P8) | Hope single CP + backups suffice undocumented |
| Age / first-boot secrets | High | Keep cidata/cloud-init delivery; never bake age key into images (P7) | Commit keys; empty placeholder files |
| CP memory floor (≥3 GiB recommended) | Medium | Import defaults + docs; guests under 2 GiB tend to leave control-plane NotReady — document loudly; optional Nix assertion later | Silent OOM loops |
| Node boilerplate / scale-out | Medium | Shared modules now; optional `nodes.nix` generator in Phase B; mandatory generation only Phase D (P5) | Copy-paste hosts with unchecked drift |
| Build times | Medium | Binary caches, pin-only bumps, baked images for cold start | Disable purity / impure host installs |
| `preloadImages` + pin bump | Medium | Live Proxmox hosts use `preloadImages = false`. When preload is on (tests/airgap), images must come from the **same** `rke2nixos.package` as the binary — see [day2-updates.md](../day2-updates.md) | Staging old image tarballs under a new RKE2 binary |
| Cilium / advanced CNI | Lower (Phase D) | Package/module + rebuild/reboot as needed (P2) | Drop binaries into `/opt` outside Nix |
| “Talos-like channel UX” | Product | Thin wrapper + pin discipline (P3, P4) | Out-of-band RKE2 |

### Bootstrap-host failure runbook (interim, until VIP)

If `bootstrapHost` (today often `server0`’s sticky IP) is permanently lost:

1. Quorum surviving CPs may keep serving workloads; **new joins and re-joins fail** until the join URL is fixed.  
2. Recover or replace the lost member per [etcd-rebuild.md](../etcd-rebuild.md) (snapshot / member remove / wipe+rejoin as appropriate).  
3. Update `bootstrapHost` (and any `tlsSans`) in the flake; redeploy **all** nodes that embed the join URL so they agree on the new target.  
4. Prefer promoting a flake-declared VIP (Phase B) before treating join as durable under HA.

---

## 8. Phased workplan (initiatives + dependencies)

Phases are ordered by dependency and P8 (prove runway). This is an initiative list, not effort estimates.

### Phase A — Design & decisions (this document)

**Depends on:** nothing. **Unblocks:** honest pin/CI/day-2 docs.

- Land this design; incorporate architect review ([issue #1](https://github.com/lucas-albers-lz4/rke2nixos/issues/1)).  
- Lock pin shape (`nixpkgs-rke2`) and PR norms (pin-only vs nixpkgs vs combined).  
- Extend day-2 docs with upgrade skew, rollback honesty (P2), and `preloadImages` interaction.  
- Capture sticky IP / DHCP reservation requirements next to `bootstrapHost`; document bootstrap-failure runbook.

### Phase B — Pin land + operability (before durable HA join)

**Depends on:** Phase A decisions. **Unblocks:** true P4; safer day-2 rolls; durable join path.

1. Land `nixpkgs-rke2` in `flake.nix`; wire default `rke2nixos.package`; exercise a live pin-only bump via `deploy-host.sh`.  
2. CI lockfile guard (fail accidental dual moves on pin PRs).  
3. Inventory-aware `rolling-upgrade.sh` (cordon/drain/deploy/wait/uncordon) wrapping `deploy-host.sh`.  
4. Optional `upgrade-rke2` thin CLI (must pass P3 guardrail).  
5. **VIP/LB bridge** for join URL (flake-declared keepalived/VRRP or equivalent) — ahead of Cilium.  
6. Optional `nodes.nix` → generated configs (checked in); hand-written hosts remain valid through Phase C.  
7. Harden age cidata / first-boot activate (already partially done); harden `deploy-host.sh` host-key verification as needed.

### Phase C — Live HA (checklist item 3)

**Depends on:** Phase B pin + preferably VIP for join resilience. **Status:** paused — scaffolding only.

- Bake/import server1/server2; join; 3 Ready CPs.  
- Practice etcd member replace once ([etcd-rebuild.md](../etcd-rebuild.md)).  
- Resolve RAM layout (keep agent vs L12 split vs pause agent)—environment decision, not principle change.

### Phase D — Later surface area

**Depends on:** Phase C live proof (P8).

- Cilium + kernel requirements.  
- aarch64/Pi hardware profiles (same `nixpkgs-rke2` commit for both arches unless forced otherwise).  
- Mandatory richer host generation from a node list (optional generator may already exist from Phase B).

Each phase should cite principles it relies on; proposals that need new principles update **§3** first.

---

## 9. Comparison frame (for external architects)

| Concern | rke2nixos stance | Talos-like | Ubuntu + Ansible + RKE2 | Kubespray-like |
|--------|------------------|------------|-------------------------|----------------|
| Node SoT | Nix flake | Machine config API | Ansible + packages | Inventory + roles |
| K8s version bump | Pin + generation apply | Channel / k8s upgrade API | Package/channel + ansible | Role vars + packages |
| OS rollback | Generations | Image A/B style | Snapshots/reimage | Snapshots/reimage |
| Etcd undo | Not implied by OS rollback | Not magic either | Not magic either | Not magic either |
| Dynamic pools | Non-goal (P5/P9) | Strength | Strength (cloud) | Strength (cloud) |
| Audit / bit identity | Strength (P3) | Strong images | Drift risk | Drift risk |
| Learning curve | Nix + flake input discipline | Lower YAML | Moderate | Moderate |

We are not trying to win the Talos column. We are trying to be the best **Nix-native RKE2** option with honest day-2 semantics.

---

## 10. Risks & mitigations

| Risk | Mitigation |
|------|------------|
| Operators treat generation rollback as K8s downgrade | Docs + deploy script warnings; upgrade runbook; P2 expanded mutable-state list |
| Pin bumps secretly float OS nixpkgs | CI lockfile diff; separate PR types; fail dual moves unless labeled combined |
| Thin upgrade CLI becomes impure SoT | P3 guardrail test; CLI only edits flake inputs + calls existing deploy |
| HA delayed → “prod” on 1 CP or sticky join | Refuse production claims until Phase C; refuse durable-join claims until VIP (Phase B) or accept sticky-host risk explicitly |
| Sticky IP / bootstrap-host loss | Reservations/static; runbook in §7; VIP in Phase B |
| Combined emergency CVE (OS + RKE2 same week) | Pin independence is a **convenience**, not a hard boundary. Test combined closure in CI; deploy as **one** rolling pass; title PR as combined bump |
| `preloadImages` mismatch after pin-only bump | Document in day-2; keep preload off on live hosts; stage images from the same package when preload is on |
| `tlsSans` / CIDR edited as if no-wipe-safe | §6.3 unsafe row; require cert rotation or re-bootstrap |

---

## 11. Success criteria

**Design accepted when reviewers can answer yes:**

1. Principles P1–P9 are clear enough to accept or amend (including P1 multi-input clarification and P3 CLI guardrail).  
2. Upgrade model is understood: pin independence via `nixpkgs-rke2` + Nix apply; mechanism decided even if not yet in-tree.  
3. Anti-designs in §6.5 are agreed or explicitly replaced.  
4. Phases A–D (with VIP in B, Cilium in D) are a sane backlog order relative to [TODO.md](../TODO.md).  
5. Open questions in §12 are resolved.

**Implementation succeeds when:**

1. `nixpkgs-rke2` is in `flake.nix` and default `rke2nixos.package` is wired from it.  
2. A documented pin-only RKE2 bump is exercised live via `deploy-host.sh` without wiping RKE2 state.  
3. Rollback / mutable-state messaging is visible in day-2 docs (and ideally a one-line deploy warning).  
4. CI enforces lockfile norms for pin vs OS bumps.  
5. Live R6 (Phase C) closes checklist item 3.  
6. No merged feature relies on out-of-band RKE2 installs.

---

## 12. Resolved decisions (from review)

| # | Topic | Decision |
|---|--------|----------|
| 1 | **Pin shape** | Dedicated flake input `nixpkgs-rke2`. Single place = that input. Pin-only bump = `nix flake lock --update-input nixpkgs-rke2`. Reject attr-only `pins.nix` as the v1 pin mechanism. |
| 2 | **Rolling automation** | Scripted inventory for v1 (`rolling-upgrade.sh` wrapping `deploy-host.sh`). No SUC-style plan controller yet. |
| 3 | **Single-CP labs** | Allowed with documented risk and explicit non-production stance. |
| 4 | **VIP timing** | Promote VIP/LB to Phase B (after pin + rolling helper, before/with durable HA join). Cilium stays Phase D. Until VIP: bootstrap-failure runbook + no production claim on sticky-host join. |
| 5 | **Host generation** | Hand-written hosts through Phase C. Optional `nodes.nix` generator in Phase B; mandatory adoption in Phase D. |
| 6 | **SSH posture** | Break-glass SSH remains first-class (P9), including for `deploy-host.sh`. Host-key hardening is follow-on script work, not a design blocker. |

---

## 13. Revision history

| Date | Change |
|------|--------|
| 2026-07-19 | Initial draft for architect review (operating principles + upgrade model) |
| 2026-07-19 | Post–issue #1 revision: lock `nixpkgs-rke2` pin; VIP→Phase B; P1/P2/P3/P7/P8 honesty; apply-path and risk table updates; resolve §12 |

**Next revision expected:** after the `nixpkgs-rke2` implementation PR lands (flip §6.1/§6.2 to as-implemented) or if principles are amended.
