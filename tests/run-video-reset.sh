#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/video_timing_pkg.vhd rtl/reset_release.vhd VIDEO/VTIMING.vhd tests/video_reset_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" video_reset_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" video_reset_tb --assert-level=error
sed 's/EXTERNAL_PIXEL_RESET=>true/EXTERNAL_PIXEL_RESET=>false/' tests/video_reset_tb.vhd > "$out/wrong-domain.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/wrong-domain.vhd"
ghdl -e --std=08 -fsynopsys --workdir="$out" video_reset_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" video_reset_tb --assert-level=error > "$out/negative.log" 2>&1; then
    echo 'FAIL: parent-domain raster reset accepted'; exit 1
fi
grep -q 'Raster counters ran before pixel reset released' "$out/negative.log"
echo 'PASS: raster reset from the wrong clock domain rejected'
