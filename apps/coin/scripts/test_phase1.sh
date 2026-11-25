#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="/tmp/mgc-phase1"
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

run test_ripemd160
run test_base58
run test_bigint
run test_secp256k1
run test_keys

echo "== keygen tool =="
"$ROOT/magc" coin/tools/keygen.mg -o "${OUT}/keygen"
"${OUT}/keygen"

echo "Phase 1: all tests passed."
