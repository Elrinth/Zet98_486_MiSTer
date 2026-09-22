#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s egc_registers_tb -o "$out/registers" \
    rtl/cpu/ao486_io_bridge.sv rtl/graphics/pc98_egc_registers.sv tests/egc_registers_tb.sv
vvp "$out/registers"
for mutation in high_lane held mask enable decode; do
    case "$mutation" in
        high_lane) sed 's/io_writedata\[15:8\]/io_writedata[7:0]/' rtl/graphics/pc98_egc_registers.sv > "$out/bad.sv" ;;
        held) sed 's/!cycle_seen/1\x27b1/' rtl/graphics/pc98_egc_registers.sv > "$out/bad.sv" ;;
        mask) sed 's/!mask_blocked/1\x27b1/' rtl/graphics/pc98_egc_registers.sv > "$out/bad.sv" ;;
        enable) sed 's/egc_enable \&\&/1\x27b1 \&\&/' rtl/graphics/pc98_egc_registers.sv > "$out/bad.sv" ;;
        decode) sed "s/io_address\[15:4\] == 12'h04a/io_address[7:4] == 4'ha/" rtl/graphics/pc98_egc_registers.sv > "$out/bad.sv" ;;
    esac
    iverilog -g2012 -s egc_registers_tb -o "$out/bad" \
        rtl/cpu/ao486_io_bridge.sv "$out/bad.sv" tests/egc_registers_tb.sv
    if vvp "$out/bad" > "$out/bad.log" 2>&1; then
        echo "FAIL: EGC register $mutation mutation accepted"; exit 1
    fi
    grep -Eq 'EGC register mismatch|EGC write pulse mismatch|EGC port decode aliases' "$out/bad.log" || { cat "$out/bad.log"; exit 1; }
    echo "PASS: EGC register $mutation mutation rejected"
done
