#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" VIDEO/video_timing_pkg.vhd VIDEO/pegc_raster.vhd LIB/div.vhd LIB/multi.vhd LIB/MATH/sqrt.vhd Zet98/GDC/calccircle.vhd Zet98/GDC/gragdc.vhd tests/gdc_pram_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_pram_tb
for gap in 8 15; do
 for delay in 0 2 9; do
  ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_pram_tb -gBUS_GAP="$gap" -gACK_DELAY="$delay" --assert-level=error --ieee-asserts=disable-at-0
 done
done
# Reintroduce the old upper-half-to-display alias. The first ninth byte must
# be rejected, independent of later drawing and reset checks.
sed 's/case PRAMADDR is/case (PRAMADDR mod 8) is/' Zet98/GDC/gragdc.vhd > "$out/alias.vhd"
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" "$out/alias.vhd" tests/gdc_pram_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_pram_tb
if ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_pram_tb --assert-level=error --ieee-asserts=disable-at-0 > "$out/negative.log" 2>&1; then
 echo 'FAIL old PRAM alias accepted';exit 1
fi
grep -q 'PRAM upper half corrupted display base0' "$out/negative.log" || { cat "$out/negative.log";exit 1; }
echo 'PASS old PRAM display alias rejected'
