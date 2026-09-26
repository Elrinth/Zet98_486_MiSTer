#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
deps=(rtl/graphics/pc98_pegc_control.sv rtl/graphics/pc98_pegc_palette.sv rtl/graphics/pc98_pegc_memory.sv tests/pc98_pegc_bus_tb.sv)
iverilog -g2012 -Wall -s pc98_pegc_bus_tb -o "$out/bus" rtl/graphics/pc98_pegc_bus.sv "${deps[@]}"
vvp "$out/bus"
sed 's/!abort_bus \&\& !completed/!abort_bus/' rtl/graphics/pc98_pegc_bus.sv > "$out/repeat.sv"
iverilog -g2012 -s pc98_pegc_bus_tb -o "$out/negative" "$out/repeat.sv" "${deps[@]}"
if vvp "$out/negative" > "$out/negative.log" 2>&1; then
    echo 'FAIL: repeated register side effects accepted';exit 1
fi
grep -q 'palette write repeated under held ACK' "$out/negative.log" || { cat "$out/negative.log";exit 1; }
echo 'PASS: repeated register side effects rejected'
