#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -I rtl/vendor/ao486 -s avalon_read_mask_tb -o "$out/check" \
    rtl/vendor/ao486/memory/avalon_mem.v tests/avalon_read_mask_tb.sv
vvp "$out/check"
sed 's/wire \[3:0\] read_burst_byteenable =.*/wire [3:0] read_burst_byteenable = 0;/' \
    rtl/vendor/ao486/memory/avalon_mem.v > "$out/bad.v"
iverilog -g2012 -I rtl/vendor/ao486 -s avalon_read_mask_tb -o "$out/bad" "$out/bad.v" tests/avalon_read_mask_tb.sv
if vvp "$out/bad" > "$out/bad.log" 2>&1; then
    echo 'FAIL: empty read-mask mutation accepted'; exit 1
fi
grep -q 'empty ao486 read mask' "$out/bad.log" || { cat "$out/bad.log"; exit 1; }
echo 'PASS: empty read-mask mutation rejected'
bash tests/run-memory-bridge.sh
iverilog -g2012 -Wall -I rtl/vendor/ao486 -s ao486_memory_integration_tb \
    -o "$out/integration" rtl/vendor/ao486/memory/avalon_mem.v \
    rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_io_bridge.sv \
    rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv tests/ao486_memory_integration_tb.sv
vvp "$out/integration"
