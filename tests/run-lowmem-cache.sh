#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for kb in 8 32 64; do
    iverilog -g2012 -Wall -s pc98_lowmem_cache_tb -Ppc98_lowmem_cache_tb.CACHE_KB="$kb" -o "$out/cache.vvp" rtl/cpu/pc98_lowmem_cache.sv tests/pc98_lowmem_cache_tb.sv
    vvp "$out/cache.vvp"
done
sed "s/else if(strobe && cacheable && write) words\[index\]<=0;/else if(1'b0) words[index]<=0;/" rtl/cpu/pc98_lowmem_cache.sv > "$out/stale.sv"
iverilog -g2012 -s pc98_lowmem_cache_tb -o "$out/stale.vvp" "$out/stale.sv" tests/pc98_lowmem_cache_tb.sv
if vvp "$out/stale.vvp" >"$out/stale.log" 2>&1; then
    echo 'FAIL: cache write-invalidation negative control passed'; exit 1
fi
grep -q 'low RAM stale read' "$out/stale.log" || { cat "$out/stale.log"; exit 1; }
echo 'PASS: low RAM negative control detects stale data after a CPU byte write'
