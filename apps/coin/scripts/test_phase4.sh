#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="/tmp/mgc-phase4"
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

run test_storage

echo "Phase 4: all tests passed."
