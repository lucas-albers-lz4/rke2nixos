# Interactive VMs (R2)

Prove a human bring-up path outside automated `nixosTest`.

## Prerequisites

- Linux host with KVM (`/dev/kvm`, user in `kvm` group)
- Flakes enabled

```bash
./scripts/smoke-vms.sh
# or:
nix build .#packages.x86_64-linux.example-server0-vm
nix build .#packages.x86_64-linux.example-agent0-vm
```

## Manual smoke

```bash
nix run .#example-server0-vm
# second terminal (after server0 is up):
nix run .#example-agent0-vm
```

Lab token is seeded by `hosts/lab-token.nix` (`lab-cluster-token-change-me`).
Join URL: `https://server0:9345` (requires the VMs to resolve/route to each other).

## Networking gaps vs `nixosTest`

| | `nixosTest` (`checks.*.server-agent`) | Interactive `build.vm` |
|--|----------------------------------------|-------------------------|
| Peer network | Test driver VLAN; nodes see each other | Default user networking / isolated TAP — **no automatic cross-VM LAN** |
| Join URL | Uses `primaryIPAddress` of server0 | Hostname `server0` only works if you add DNS/hosts or shared bridge |
| Token | `tests/lib.nix` store path | Activation-script lab token |
| SSH | Via test driver | Port forward / serial console (`nixos` / `nixos`) |

### Making interactive VMs join each other

1. Shared bridge (recommended): run both VMs with a custom QEMU netdev on the same bridge, or use `QEMU_NET_OPTS` / a small libvirt network.
2. Or point the agent `joinUrl` at the server’s reachable IP and rebuild `example-agent0`.
3. Prefer `nix build .#checks.x86_64-linux.server-agent` for automated multi-node confidence; use interactive VMs for SSH/console exploration of a **single** node, or after wiring a shared network.

## Success criteria

- VM runners build successfully (`./scripts/smoke-vms.sh`)
- Single-node interactive boot reaches login (serial)
- Multi-node join validated via QEMU checks (not required inside Docker/CI)
