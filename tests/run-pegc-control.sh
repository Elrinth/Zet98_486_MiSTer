#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s pc98_pegc_control_tb -o "$out/control" \
    rtl/graphics/pc98_pegc_control.sv tests/pc98_pegc_control_tb.sv
vvp "$out/control"
# Reject the previous four-bit palette-index limitation.
sed 's/palette_index <= io_writedata\[7:0\]/palette_index <= {4\x27h0,io_writedata[3:0]}/' \
    rtl/graphics/pc98_pegc_control.sv > "$out/broken.sv"
iverilog -g2012 -s pc98_pegc_control_tb -o "$out/negative" "$out/broken.sv" tests/pc98_pegc_control_tb.sv
if vvp "$out/negative" > "$out/negative.log" 2>&1; then
    echo 'FAIL: four-bit PEGC palette index accepted';exit 1
fi
grep -q 'palette index aliases or truncated' "$out/negative.log" || { cat "$out/negative.log";exit 1; }
echo 'PASS: truncated palette index negative control rejected'
