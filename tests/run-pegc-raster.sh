#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/video_timing_pkg.vhd VIDEO/pegc_raster.vhd tests/pegc_raster_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" pegc_raster_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" pegc_raster_tb --assert-level=error --ieee-asserts=disable-at-0
sed "s/base0_p \& '0'/('0' \& base0_p)/g" VIDEO/pegc_raster.vhd > "$out/wrong.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/wrong.vhd" tests/pegc_raster_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" pegc_raster_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" pegc_raster_tb --assert-level=error --ieee-asserts=disable-at-0 > "$out/negative.log" 2>&1; then
    echo 'FAIL: incorrect SAD units accepted';exit 1
fi
grep -q 'packed row address/pitch/page/repeat mismatch' "$out/negative.log"
echo 'PASS: incorrect SAD units rejected'
# Restore the B153 behavior: this doubled the hardware BIOS probe and cropped
# the original Doom title. The independent packed-row reference must reject it.
sed "s/pitch_p<=unsigned(pitch);repeat_p<=(others=>'0');/pitch_p<=unsigned(pitch);repeat_p<=unsigned(repeat_lines);/" VIDEO/pegc_raster.vhd > "$out/legacy-repeat.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/legacy-repeat.vhd" tests/pegc_raster_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" pegc_raster_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" pegc_raster_tb --assert-level=error --ieee-asserts=disable-at-0 > "$out/repeat-negative.log" 2>&1; then
    echo 'FAIL: legacy row repetition in packed mode accepted';exit 1
fi
grep -q 'packed row address/pitch/page/repeat mismatch' "$out/repeat-negative.log"
echo 'PASS: legacy row repetition in packed mode rejected'
bash tests/run-pegc-line.sh
