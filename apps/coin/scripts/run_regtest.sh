#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$ROOT/build"
cd "$ROOT"

echo "== build =="
"$ROOT/magc" coin/main.mg -o "$ROOT/build/mgcd"
"$ROOT/magc" coin/main.mg -o "$ROOT/build/mgc-cli"

NODE_PID=""
LOG="/tmp/mgc-regtest.log"
cleanup() {
    if [ -n "$NODE_PID" ]; then
        kill "$NODE_PID" 2>/dev/null || true
        wait "$NODE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

rm -rf /tmp/mgc-regtest
"$ROOT/build/mgcd" --datadir=/tmp/mgc-regtest >"$LOG" 2>&1 &
NODE_PID=$!
sleep 1

CLI="$ROOT/build/mgc-cli"
for i in $(seq 1 50); do
    if ! kill -0 "$NODE_PID" 2>/dev/null; then
        echo "node exited during startup"
        cat "$LOG"
        exit 1
    fi
    if "$CLI" --datadir=/tmp/mgc-regtest getblockchaininfo >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

echo "== getblockchaininfo =="
"$CLI" --datadir=/tmp/mgc-regtest getblockchaininfo
echo "== getnewaddress =="
"$CLI" --datadir=/tmp/mgc-regtest getnewaddress
echo "== generate 101 =="
if ! "$CLI" --datadir=/tmp/mgc-regtest generate 101; then
    echo "generate 101 did not return within the CLI timeout"
fi
echo "== getbalance =="
"$CLI" --datadir=/tmp/mgc-regtest getbalance
echo "== stop =="
"$CLI" --datadir=/tmp/mgc-regtest stop
for i in $(seq 1 50); do
    if ! kill -0 "$NODE_PID" 2>/dev/null; then
        NODE_PID=""
        break
    fi
    sleep 0.1
done

echo "Regtest smoke test complete."
