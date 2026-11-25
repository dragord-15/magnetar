#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="/tmp/mgc-crash-recovery"
DD="${OUT}/regtest"
PORT=29461
RPC=29452
NODE="${OUT}/mgcd"
CLI="${OUT}/mgc-cli"
NPID=""

cleanup() {
    if [ -n "${NPID}" ] && kill -0 "${NPID}" 2>/dev/null; then
        kill -9 "${NPID}" 2>/dev/null || true
        wait "${NPID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

rm -rf "${OUT}"
mkdir -p "${OUT}"
cd "${ROOT}"
"${ROOT}/magc" coin/main.mg -o "${NODE}"
cp "${NODE}" "${CLI}"

start_node() {
    "${NODE}" --datadir="${DD}" --port=${PORT} --rpcport=${RPC} >"${1}" 2>&1 &
    NPID=$!
    for _ in $(seq 1 120); do
        if ! kill -0 "${NPID}" 2>/dev/null; then
            echo "node exited unexpectedly"
            cat "${1}"
            return 1
        fi
        if "${CLI}" --datadir="${DD}" --rpcport=${RPC} getblockcount >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done
    echo "node did not become ready"
    return 1
}

rpc() {
    "${CLI}" --datadir="${DD}" --rpcport=${RPC} "$@"
}

expect_result() {
    local label="$1"
    local expected="$2"
    shift 2
    local out
    out="$(rpc "$@")"
    if ! printf '%s' "${out}" | grep -q "\"result\":${expected}"; then
        echo "FAIL ${label}: expected ${expected}, got ${out}"
        return 1
    fi
    echo "PASS ${label}"
}

start_node "${OUT}/node-1.log"
rpc getnewaddress >/dev/null
rpc generate 2 >/dev/null
expect_result "initial blocks" 2 getblockcount
expect_result "initial balance" 10000000000 getbalance
rpc stop >/dev/null
wait "${NPID}"
NPID=""

start_node "${OUT}/node-2.log"
expect_result "blocks after restart" 2 getblockcount
expect_result "balance after restart" 10000000000 getbalance
rpc generate 3 >/dev/null
expect_result "blocks after mining" 5 getblockcount
expect_result "balance after mining" 25000000000 getbalance
kill -9 "${NPID}"
wait "${NPID}" 2>/dev/null || true
NPID=""

# A missing UTXO snapshot must be rebuilt from the block log.
rm -f "${DD}/chainstate/utxo.dat"
start_node "${OUT}/node-3.log"
expect_result "blocks after kill -9 + reindex" 5 getblockcount
expect_result "balance after kill -9 + reindex" 25000000000 getbalance
rpc stop >/dev/null
wait "${NPID}"
NPID=""

# Restore a copy of the datadir into a fresh path.
cp -a "${DD}" "${OUT}/restored"
DD="${OUT}/restored"
PORT=29471
RPC=29462
start_node "${OUT}/node-backup.log"
expect_result "blocks after backup restore" 5 getblockcount
expect_result "balance after backup restore" 25000000000 getbalance
rpc stop >/dev/null
wait "${NPID}"
NPID=""

echo "Crash recovery and backup restore test passed."
