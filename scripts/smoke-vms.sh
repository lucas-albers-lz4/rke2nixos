#!/usr/bin/env bash
# Smoke-build interactive VM runners (does not leave VMs running).
# Full manual smoke: see docs/interactive-vms.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes
warn-dirty = false}"

echo "Building example-server0-vm and example-agent0-vm…"
nix build .#packages.x86_64-linux.example-server0-vm --out-link result-server-vm
nix build .#packages.x86_64-linux.example-agent0-vm --out-link result-agent-vm
echo "OK: result-server-vm and result-agent-vm"
echo "Run manually (Linux + KVM): nix run .#example-server0-vm"
