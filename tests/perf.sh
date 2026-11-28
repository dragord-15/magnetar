#!/usr/bin/env bash
# Measurement harness for docs_mag/26_performance_diagnosis.md.
# The canonical numbers in that chapter were measured on x86_64; this script
# reproduces the same workloads on the current host (aarch64 here) so every
# fix can be checked for regressions even without an x86_64 runner.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAGC="${MAGC:-$ROOT/magc}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Compile speed and ELF sizes are measured with the x86_64 backend, exactly as
# in chapter 26. Runtime/instruction counts need a runner, so they use ARM64
# (the native target on this host).
TARGET="${TARGET:-arm64}"
BUILD_TARGET="${BUILD_TARGET:-x86_64}"
LOOP_N="${LOOP_N:-10000000}"
RUNS="${RUNS:-5}"
target_flag="--target $TARGET"
build_flag="--target $BUILD_TARGET"

now_ns() { date +%s%N; }

median() {
  printf '%s\n' "$@" | sort -n | awk 'NR==2 {print $1}'
}

echo "=== Magnetar performance probe (target=$TARGET, loop=$LOOP_N) ==="

# 1) compile speed: 2000 trivial functions + main
{
  for i in $(seq 1 2000); do printf 'fn f%d(int x) -> int { return x + %d; }\n' "$i" "$i"; done
  printf 'fn main() -> int { return f1(1); }\n'
} > "$WORK/funcs.mg"
compile=()
for i in $(seq 1 "$RUNS"); do
  t0="$(now_ns)"
  "$MAGC" "$WORK/funcs.mg" $build_flag -o "$WORK/funcs" >/dev/null 2>&1 || { echo "compile failed"; exit 1; }
  t1="$(now_ns)"
  compile+=("$(( (t1 - t0) / 1000000 ))")
done
echo "compile 2000 functions: $(median "${compile[@]}") ms (median of $RUNS)"

# 2) ELF sizes (the exact same programs used in chapter 26)
printf 'fn main() -> int { return 0; }\n' > "$WORK/empty.mg"
printf 'extern fn sys_clock_gettime(int clk, int* tp) -> int;\nfn main() -> int { return 0; }\n' > "$WORK/loop.mg"
printf 'use "lib/algorithm.mg";\nuse "lib/hashmap.mg";\nfn main() -> int { return 0; }\n' > "$WORK/both.mg"
printf 'use "lib/gui.mg";\nfn main() -> int { return 0; }\n' > "$WORK/gui.mg"
for name in empty loop both gui; do
  if "$MAGC" "$WORK/$name.mg" $build_flag -o "$WORK/$name" >/dev/null 2>&1; then
    echo "ELF $name: $(stat -c %s "$WORK/$name") bytes"
  else
    echo "ELF $name: compile failed"
  fi
done

# 3) loop execution time and instructions per iteration (1M subset for callgrind)
cat > "$WORK/bench.mg" <<EOF
fn kernel(int n) -> int {
    int s = 0; int i = 0;
    while (i < n) { s = s + ((i * 3) ^ (i >> 1)); i = i + 1; }
    return s;
}
fn main() -> int { print(kernel($LOOP_N)); print("\\n"); return 0; }
EOF
"$MAGC" "$WORK/bench.mg" $target_flag -o "$WORK/bench" >/dev/null 2>&1 || { echo "bench compile failed"; exit 1; }
times=()
for i in $(seq 1 "$RUNS"); do
  t0="$(now_ns)"; "$WORK/bench" >/dev/null; t1="$(now_ns)"
  times+=("$(( (t1 - t0) / 1000000 ))")
done
echo "loop $LOOP_N: $(median "${times[@]}") ms (median of $RUNS)"

if command -v valgrind >/dev/null 2>&1; then
  sed "s/$LOOP_N/1000000/" "$WORK/bench.mg" > "$WORK/bench1m.mg"
  "$MAGC" "$WORK/bench1m.mg" $target_flag -o "$WORK/bench1m" >/dev/null 2>&1
  refs="$(valgrind --tool=callgrind --callgrind-out-file=/dev/null "$WORK/bench1m" 2>&1 | awk '/I +refs:/ {gsub(/,/,"",$4); print $4}')"
  if [[ -n "${refs:-}" ]]; then
    echo "instructions/iteration (1M subset): $(( refs / 1000000 ))"
  fi
fi
