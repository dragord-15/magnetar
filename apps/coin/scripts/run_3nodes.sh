#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$ROOT/build"
cd "$ROOT"

echo "== build =="
"$ROOT/magc" coin/main.mg -o "$ROOT/build/mgcd"
"$ROOT/magc" coin/main.mg -o "$ROOT/build/mgc-cli"

CLI="$ROOT/build/mgc-cli"
NODE_PIDS=""
cleanup() {
    for pid in $NODE_PIDS; do
        kill "$pid" 2>/dev/null || true
    done
    for pid in $NODE_PIDS; do
        wait "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT

cli_node() {
    local n="$1"
    shift
    case "$n" in
        1) "$CLI" --datadir=/tmp/mgc-node1 --rpcport=29332 "$@" ;;
        2) "$CLI" --datadir=/tmp/mgc-node2 --rpcport=29344 "$@" ;;
        3) "$CLI" --datadir=/tmp/mgc-node3 --rpcport=29345 "$@" ;;
    esac
}

cli_node_timeout() {
    local secs="$1"
    local n="$2"
    shift 2
    case "$n" in
        1) timeout "$secs" "$CLI" --datadir=/tmp/mgc-node1 --rpcport=29332 "$@" ;;
        2) timeout "$secs" "$CLI" --datadir=/tmp/mgc-node2 --rpcport=29344 "$@" ;;
        3) timeout "$secs" "$CLI" --datadir=/tmp/mgc-node3 --rpcport=29345 "$@" ;;
    esac
}

wait_ready() {
    local n="$1"
    local pid="$2"
    local i
    for i in $(seq 1 100); do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "node${n} exited during startup"
            cat "/tmp/mgc-node${n}.log"
            exit 1
        fi
        if cli_node "$n" getblockcount >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    echo "node${n} did not become ready"
    exit 1
}

rm -rf /tmp/mgc-node1 /tmp/mgc-node2 /tmp/mgc-node3

"$ROOT/build/mgcd" --datadir=/tmp/mgc-node1 --port=29341 --rpcport=29332 >/tmp/mgc-node1.log 2>&1 &
NODE1_PID=$!
"$ROOT/build/mgcd" --datadir=/tmp/mgc-node2 --port=29342 --rpcport=29344 >/tmp/mgc-node2.log 2>&1 &
NODE2_PID=$!
"$ROOT/build/mgcd" --datadir=/tmp/mgc-node3 --port=29343 --rpcport=29345 >/tmp/mgc-node3.log 2>&1 &
NODE3_PID=$!
NODE_PIDS="$NODE1_PID $NODE2_PID $NODE3_PID"

wait_ready 1 "$NODE1_PID"
wait_ready 2 "$NODE2_PID"
wait_ready 3 "$NODE3_PID"

echo "== addnode =="
cli_node 2 addnode 127.0.0.1:29341
cli_node 3 addnode 127.0.0.1:29341
sleep 2

for n in 1 2 3; do
    echo "== node${n} getblockcount =="
    cli_node "$n" getblockcount
done

echo "== generate 5 on node1 =="
cli_node 1 generate 5
sleep 2

for n in 1 2 3; do
    echo "== node${n} getblockcount after mining =="
    cli_node "$n" getblockcount
done

for n in 1 2 3; do
    echo "== node${n} getpeerinfo =="
    if ! cli_node_timeout 12 "$n" getpeerinfo; then
        echo "node${n} getpeerinfo timed out"
    fi
done

echo "3-node regtest smoke test complete."
