#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NETWORK="${NETWORK:-test}"
DURATION_SECONDS="${DURATION_SECONDS:-259200}"
BLOCK_INTERVAL="${BLOCK_INTERVAL:-120}"
DATADIR_ROOT="${DATADIR_ROOT:-/tmp/mgc-testnet-soak}"
LOG_DIR="${LOG_DIR:-${DATADIR_ROOT}/logs}"
NODE="$ROOT/build/mgcd-soak"
CLI="$ROOT/build/mgc-cli-soak"
NODE_PIDS=()

cleanup() {
    for pid in "${NODE_PIDS[@]}"; do
        kill "${pid}" 2>/dev/null || true
    done
    for pid in "${NODE_PIDS[@]}"; do
        wait "${pid}" 2>/dev/null || true
    done
}
trap cleanup EXIT

mkdir -p "${ROOT}/build" "${LOG_DIR}"
cd "${ROOT}"
"${ROOT}/magc" coin/main.mg -o "${NODE}" >/dev/null
cp "${NODE}" "${CLI}"

if [ "${KEEP_DATA:-0}" != "1" ]; then
    rm -rf "${DATADIR_ROOT}/node1" "${DATADIR_ROOT}/node2" "${DATADIR_ROOT}/node3"
fi

start_node() {
    local n="$1" port="$2" rpcport="$3"
    local datadir="${DATADIR_ROOT}/node${n}"
    "${NODE}" --network="${NETWORK}" --datadir="${datadir}" --port="${port}" --rpcport="${rpcport}" \
        >"${LOG_DIR}/node${n}.log" 2>&1 &
    NODE_PIDS+=("$!")
    for _ in $(seq 1 120); do
        if "${CLI}" --datadir="${datadir}" --rpcport="${rpcport}" getblockcount >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done
    echo "node${n} failed to start"
    return 1
}

start_node 1 29581 29582
start_node 2 29583 29584
start_node 3 29585 29586

"${CLI}" --datadir="${DATADIR_ROOT}/node2" --rpcport=29584 addnode 127.0.0.1:29581 >/dev/null
"${CLI}" --datadir="${DATADIR_ROOT}/node3" --rpcport=29586 addnode 127.0.0.1:29581 >/dev/null
sleep 2

START_TS="$(date +%s)"
END_TS=$((START_TS + DURATION_SECONDS))
BLOCKS=0
echo "network=${NETWORK} duration=${DURATION_SECONDS}s interval=${BLOCK_INTERVAL}s datadir=${DATADIR_ROOT}"
echo "timestamp,block,height1,height2,height3,rss1_kb,rss2_kb,rss3_kb"

while [ "$(date +%s)" -lt "${END_TS}" ]; do
    "${CLI}" --datadir="${DATADIR_ROOT}/node1" --rpcport=29582 generate 1 >/dev/null
    BLOCKS=$((BLOCKS + 1))
    sleep 2
    h1="$("${CLI}" --datadir="${DATADIR_ROOT}/node1" --rpcport=29582 getblockcount | sed -E 's/.*"result":([0-9]+).*/\1/')"
    h2="$("${CLI}" --datadir="${DATADIR_ROOT}/node2" --rpcport=29584 getblockcount | sed -E 's/.*"result":([0-9]+).*/\1/')"
    h3="$("${CLI}" --datadir="${DATADIR_ROOT}/node3" --rpcport=29586 getblockcount | sed -E 's/.*"result":([0-9]+).*/\1/')"
    r1="$(ps -o rss= -p "${NODE_PIDS[0]}" 2>/dev/null | tr -d ' ')"
    r2="$(ps -o rss= -p "${NODE_PIDS[1]}" 2>/dev/null | tr -d ' ')"
    r3="$(ps -o rss= -p "${NODE_PIDS[2]}" 2>/dev/null | tr -d ' ')"
    echo "$(date +%s),${BLOCKS},${h1},${h2},${h3},${r1:-0},${r2:-0},${r3:-0}"
    if [ "${h1}" != "${h2}" ] || [ "${h1}" != "${h3}" ]; then
        echo "consensus mismatch at block ${BLOCKS}: ${h1}/${h2}/${h3}" >&2
        exit 1
    fi
    remaining=$((END_TS - $(date +%s)))
    if [ "${remaining}" -le 0 ]; then break; fi
    pause="${BLOCK_INTERVAL}"
    if [ "${pause}" -gt "${remaining}" ]; then pause="${remaining}"; fi
    sleep "${pause}"
done

for n in 1 2 3; do
    "${CLI}" --datadir="${DATADIR_ROOT}/node${n}" --rpcport="$((29582 + (n - 1) * 2))" stop >/dev/null 2>&1 || true
done
for pid in "${NODE_PIDS[@]}"; do
    wait "${pid}" 2>/dev/null || true
done
NODE_PIDS=()
echo "soak complete: blocks=${BLOCKS}"
