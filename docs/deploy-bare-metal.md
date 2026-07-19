# Deploy on bare metal (R5)

Same flake roles as Proxmox; different disk/NIC profile.

## Paths

1. **Installer ISO** → `nixos-install` from `.#packages.x86_64-linux.installer-iso`
2. **Pre-imaged disk** — build a disk image with the bare-metal profile (extend flake similarly to Proxmox qcow2), flash to disk
3. **Existing NixOS** — `./scripts/deploy-host.sh bare-metal-server0 root@<ip>`

## Before first install

Edit `hosts/bare-metal/server0.nix` / `agent0.nix`:

- Root SSH keys
- Real NIC name / static IP (or DHCP)
- `fileSystems` / bootloader if not label-based `nixos` + `ESP`
- Optional dedicated filesystem for `/var/lib/rancher/rke2`

Install age key to `/var/lib/sops-nix/key.txt` before switch (or in the installed system before reboot into RKE2).

## Bring-up

1. Install/boot **server0** (`bootstrap = true`)
2. Point agent `joinUrl` at `https://<server0-ip>:9345`
3. Install/boot **agent0**
4. `kubectl get nodes` on server0

## Success criteria

Same as Proxmox R5: 1+1 Ready, sops token, RKE2 state persists across generations.
