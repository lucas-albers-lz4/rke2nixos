#!/usr/bin/env bash
# Run nix commands in nixos/nix with the repo bind-mounted.
# Usage: ./scripts/nix-docker.sh nix flake show
#        ./scripts/nix-docker.sh nix build .#packages.x86_64-linux.example-server0
#
# Optional: NIX_DOCKER_IMAGE (default nixos/nix:latest)
# Optional: NIX_DOCKER_EXTRA_ARGS — extra docker run flags (e.g. --device /dev/kvm later)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${NIX_DOCKER_IMAGE:-nixos/nix:latest}"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker is required" >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  set -- bash
fi

docker_tty=()
if [[ -t 0 && -t 1 ]]; then
  docker_tty+=(-it)
elif [[ -t 0 ]]; then
  docker_tty+=(-i)
fi

extra=()
if [[ -n "${NIX_DOCKER_EXTRA_ARGS:-}" ]]; then
  # intentional split for user-supplied docker flags
  # shellcheck disable=SC2206
  extra=(${NIX_DOCKER_EXTRA_ARGS})
fi

# Flakes need Git; bind mounts are often not "owned" by the container user (libgit2).
# Mark the workdir safe before running the user's command.
exec docker run --rm "${docker_tty[@]}" \
  -v "${ROOT}:/work:rw" \
  -w /work \
  -e NIX_CONFIG="experimental-features = nix-command flakes"$'\n'"warn-dirty = false" \
  "${extra[@]}" \
  "${IMAGE}" \
  bash -lc 'git config --global --add safe.directory /work; exec "$@"' -- "$@"
