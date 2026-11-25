#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="/tmp/mgc-phase5"
mkdir -p "$OUT"

run() {
    local name="$1"
    local src="coin/tests/${name}.mg"
    local bin="${OUT}/${name}"
    echo "== ${name} =="
    "$ROOT/magc" "$src" -o "$bin"
    "$bin"
}

cd "$ROOT"

run test_p2p
run test_addrman
run test_peer_sync

echo "Phase 5: all tests passed."
