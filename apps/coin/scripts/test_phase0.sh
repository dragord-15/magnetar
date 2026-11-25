#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="/tmp/mcg-phase0"
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

run test_endian
run test_varint
run test_hash
run test_serialization
run test_params

echo "== main scaffold =="
"$ROOT/magc" coin/main.mg -o "${OUT}/mgcd"
"${OUT}/mgcd"

echo "Phase 0: all tests passed."
