#!/usr/bin/env bash
# Fix existing rke2nixos VMs that hang at "Booting From Hard Disk":
# baked images are EFI; Proxmox default SeaBIOS cannot boot them.
#
# Run on the node that owns the VMs (L11), as root:
#   ./scripts/proxmox-fix-uefi-boot.sh 200 201
set -euo pipefail

STORAGE="${PROXMOX_STORAGE:-local-lvm}"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <vmid> [vmid...]" >&2
  exit 1
fi

command -v qm >/dev/null 2>&1 || {
  echo "error: run on a Proxmox node with qm" >&2
  exit 1
}

for v in "$@"; do
  echo "=== fixing VM $v for OVMF/UEFI ==="
  qm stop "$v" 2>/dev/null || true
  # wait until stopped
  for _ in $(seq 1 60); do
    qm status "$v" 2>/dev/null | grep -q stopped && break
    sleep 1
  done

  qm set "$v" --bios ovmf
  qm set "$v" --machine q35
  # Add EFI vars disk if missing
  if ! qm config "$v" | grep -q '^efidisk0:'; then
    qm set "$v" --efidisk0 "${STORAGE}:1,efitype=4m,pre-enrolled-keys=0"
  fi

  # VM 200 had a leftover unused0 from an earlier import — prefer it if present
  if qm config "$v" | grep -q '^unused0:'; then
    echo "note: unused0 disk present on $v — if UEFI still fails, swap scsi0 with unused0 in the UI"
  fi

  qm start "$v"
  echo "started $v — use: qm terminal $v"
done
