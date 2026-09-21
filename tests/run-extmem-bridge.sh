#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for cache in 0 1; do
    iverilog -g2012 -Wall -s pc98_extmem_bridge_tb -Ppc98_extmem_bridge_tb.READ_CACHE="$cache" \
        -o "$out/extmem.vvp" rtl/cpu/pc98_extmem_bridge.sv tests/pc98_extmem_bridge_tb.sv
    vvp "$out/extmem.vvp"
done
awk 'index($0,"if(READ_CACHE && line_valid && line_address==held_address[31:3])") {
    $0="                    if(0)"; changes++
} {print} END {if(changes!=1) exit 1}' rtl/cpu/pc98_extmem_bridge.sv > "$out/broken.sv"
iverilog -g2012 -s pc98_extmem_bridge_tb -o "$out/negative.vvp" "$out/broken.sv" tests/pc98_extmem_bridge_tb.sv
if vvp "$out/negative.vvp" >"$out/negative.log" 2>&1; then
    echo 'FAIL: stale DDR buffer negative control passed'; exit 1
fi
grep -q 'extended RAM byte-write/read mismatch' "$out/negative.log" || { cat "$out/negative.log"; exit 1; }
echo 'PASS: DDR buffer negative control detects missing byte-write coherence'
