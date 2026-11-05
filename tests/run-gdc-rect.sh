#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" LIB/div.vhd LIB/multi.vhd LIB/MATH/sqrt.vhd Zet98/GDC/calccircle.vhd Zet98/GDC/gragdc.vhd tests/gdc_rect_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_rect_tb
for delay in 0 2 9; do
 ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_rect_tb -gACK_DELAY="$delay" --assert-level=error --ieee-asserts=disable-at-0
done
# Negative control: removing the retirement decrement must be detected.
sed '/D_NUM<=D_NUM-1;/d' Zet98/GDC/gragdc.vhd > "$out/no-decrement.vhd"
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" "$out/no-decrement.vhd" tests/gdc_rect_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_rect_tb
if ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_rect_tb --assert-level=error --ieee-asserts=disable-at-0 > "$out/negative.log" 2>&1; then
 echo 'FAIL non-terminating rectangle accepted';exit 1
fi
grep -Eq 'rectangle (never completes|busy never clears)' "$out/negative.log" || { cat "$out/negative.log";exit 1; }
echo 'PASS non-terminating rectangle rejected'
