#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
src="VIDEO/video_timing_pkg.vhd LIB/div.vhd LIB/multi.vhd LIB/MATH/sqrt.vhd Zet98/GDC/calccircle.vhd"
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" $src Zet98/GDC/gragdc.vhd tests/gdc_sync_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_sync_tb
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_sync_tb --assert-level=error --ieee-asserts=disable-at-0
# The old decoder ignored SYNC's DE bit: it must fail on the bare SYNC.
sed -e 's/when x"6b" | x"0d" | x"0f" =>/when x"6b" | x"0d" =>/' \
    -e 's/when x"0c" | x"0e" =>/when x"0c" =>/' Zet98/GDC/gragdc.vhd > "$out/old.vhd"
if cmp -s Zet98/GDC/gragdc.vhd "$out/old.vhd"; then echo 'FAIL could not recreate the old decoder';exit 1;fi
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" "$out/old.vhd" tests/gdc_sync_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_sync_tb
if ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_sync_tb --assert-level=error --ieee-asserts=disable-at-0 > "$out/negative.log" 2>&1; then
 echo 'FAIL old decoder accepted';exit 1
fi
grep -q 'SYNC 0Eh: GRAPHEN' "$out/negative.log" || { cat "$out/negative.log";exit 1; }
echo 'PASS old decoder rejected (SYNC ignored)'
