#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for narrow in 0 1; do
    for skip in 0 1; do
        iverilog -g2012 -Wall -s ao486_memory_bridge_tb \
            -Pao486_memory_bridge_tb.NARROW_READS="$narrow" \
            -Pao486_memory_bridge_tb.SKIP_EMPTY_HALVES="$skip" \
            -o "$out/memory.vvp" rtl/cpu/ao486_memory_bridge.sv tests/ao486_memory_bridge_tb.sv
        vvp "$out/memory.vvp" | tee "$out/$skip.log"
    done
    before=$(sed -n 's/^memory_bridge_cycles=//p' "$out/0.log")
    after=$(sed -n 's/^memory_bridge_cycles=//p' "$out/1.log")
    if [[ -z "$before" || -z "$after" || "$after" -ge "$before" ]]; then
        echo 'FAIL: skipping empty halves did not shorten the same checked workload' >&2
        exit 1
    fi
    echo "PASS: same memory workload, narrow=$narrow, $before -> $after clocks"
done
