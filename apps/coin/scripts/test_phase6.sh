#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="/tmp/mgc-phase6"
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

run test_json
run test_wallet
run test_rpc

echo "== node binary =="
"$ROOT/magc" coin/main.mg -o /tmp/mgc-node

echo "Phase 6: all tests passed."
