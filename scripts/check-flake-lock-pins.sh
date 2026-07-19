#!/usr/bin/env bash
# Fail if flake.lock moves both nixpkgs and nixpkgs-rke2 unless this is an
# explicit combined bump (PR title starts with "combined:" or label combined-bump).
#
# Usage:
#   scripts/check-flake-lock-pins.sh              # compare against origin/master (or HEAD~1)
#   scripts/check-flake-lock-pins.sh <base-ref>   # compare against git ref
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_REF="${1:-}"
if [[ -z "$BASE_REF" ]]; then
  if git rev-parse --verify origin/master >/dev/null 2>&1; then
    BASE_REF="origin/master"
  else
    BASE_REF="HEAD~1"
  fi
fi

if ! git cat-file -e "${BASE_REF}:flake.lock" 2>/dev/null; then
  echo "check-flake-lock-pins: no flake.lock at ${BASE_REF}; skipping"
  exit 0
fi

if git diff --quiet "${BASE_REF}" -- flake.lock; then
  echo "check-flake-lock-pins: flake.lock unchanged; ok"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git show "${BASE_REF}:flake.lock" >"$tmp/old.lock"
cp flake.lock "$tmp/new.lock"

node_rev() {
  local lock="$1" name="$2"
  python3 - "$lock" "$name" <<'PY'
import json, sys
lock, name = sys.argv[1], sys.argv[2]
data = json.load(open(lock))
node = data.get("nodes", {}).get(name)
if not node:
    print("")
    sys.exit(0)
locked = node.get("locked") or {}
print(locked.get("rev") or locked.get("narHash") or "")
PY
}

old_nixpkgs="$(node_rev "$tmp/old.lock" nixpkgs)"
new_nixpkgs="$(node_rev "$tmp/new.lock" nixpkgs)"
old_rke2="$(node_rev "$tmp/old.lock" nixpkgs-rke2)"
new_rke2="$(node_rev "$tmp/new.lock" nixpkgs-rke2)"

nixpkgs_moved=0
rke2_moved=0
[[ "$old_nixpkgs" != "$new_nixpkgs" ]] && nixpkgs_moved=1
# Missing → present counts as a move (initial pin land).
[[ "$old_rke2" != "$new_rke2" ]] && rke2_moved=1

echo "check-flake-lock-pins: nixpkgs moved=${nixpkgs_moved} (${old_nixpkgs:0:12}→${new_nixpkgs:0:12})"
echo "check-flake-lock-pins: nixpkgs-rke2 moved=${rke2_moved} (${old_rke2:0:12}→${new_rke2:0:12})"

if [[ "$nixpkgs_moved" -eq 0 || "$rke2_moved" -eq 0 ]]; then
  echo "check-flake-lock-pins: ok (not a dual move)"
  exit 0
fi

# Combined bump escape hatch
title="${PR_TITLE:-${GITHUB_PR_TITLE:-}}"
labels="${PR_LABELS:-}"
if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "${GITHUB_EVENT_PATH}" ]]; then
  title="$(python3 -c 'import json,os; e=json.load(open(os.environ["GITHUB_EVENT_PATH"])); print((e.get("pull_request") or {}).get("title") or "")' 2>/dev/null || true)"
  labels="$(python3 -c 'import json,os; e=json.load(open(os.environ["GITHUB_EVENT_PATH"])); print(",".join(l["name"] for l in ((e.get("pull_request") or {}).get("labels") or [])))' 2>/dev/null || true)"
fi

combined=0
[[ "${title,,}" == combined:* ]] && combined=1
[[ ",${labels}," == *",combined-bump,"* ]] && combined=1
[[ "${ALLOW_COMBINED_LOCK_BUMP:-0}" == "1" ]] && combined=1

if [[ "$combined" -eq 1 ]]; then
  echo "check-flake-lock-pins: dual move allowed (combined bump)"
  exit 0
fi

echo "error: flake.lock moved both nixpkgs and nixpkgs-rke2." >&2
echo "  For a pin-only bump, update only nixpkgs-rke2." >&2
echo "  For an OS bump, update nixpkgs (and sops-nix); leave nixpkgs-rke2 unless intentional." >&2
echo "  For a combined emergency bump, title the PR 'combined: …' or add label combined-bump." >&2
exit 1
