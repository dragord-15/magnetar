#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="/tmp/mgc-all"
mkdir -p "$OUT"

cd "$ROOT"

echo "== phase 0 =="
DEFAULT_ROOT="$ROOT/MagnetarEnvVal"
mkdir -p "$DEFAULT_ROOT/.mgc"
"$ROOT/magc" coin/main.mg -o "${OUT}/mgc-cli"
(
    for i in $(seq 1 300); do
        if "${OUT}/mgc-cli" --datadir="${DEFAULT_ROOT}/.mgc/regtest" stop >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
) &
WATCHER_PID=$!
cleanup_phase0() {
    kill "$WATCHER_PID" 2>/dev/null || true
    wait "$WATCHER_PID" 2>/dev/null || true
    rm -rf "$DEFAULT_ROOT"
}
trap cleanup_phase0 EXIT
bash coin/scripts/test_phase0.sh
cleanup_phase0
trap - EXIT

echo "== phase 1 =="
bash coin/scripts/test_phase1.sh

echo "== phase 2 =="
bash coin/scripts/test_phase2.sh

echo "== phase 3 =="
bash coin/scripts/test_phase3.sh

echo "== phase 4 =="
bash coin/scripts/test_phase4.sh

echo "== phase 5 =="
bash coin/scripts/test_phase5.sh

echo "== phase 6 =="
bash coin/scripts/test_phase6.sh

echo "== phase 7 tools =="
"$ROOT/magc" coin/tools/genesis.mg -o "${OUT}/genesis"
"${OUT}/genesis"
"$ROOT/magc" coin/tools/bench_sha256.mg -o "${OUT}/bench_sha256"
"${OUT}/bench_sha256"
"$ROOT/magc" coin/tools/fuzz_deserialize.mg -o "${OUT}/fuzz_deserialize"
"${OUT}/fuzz_deserialize"

echo "All phases and tools passed."
