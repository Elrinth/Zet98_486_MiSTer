#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/video_timing_pkg.vhd LIB/delayer.vhd VIDEO/GRAPHSCR98.vhd tests/graphics_address_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" graphics_address_tb
for length in 1 3 200 400 513 1023 0; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" graphics_address_tb -gFIRST_LENGTH="$length" --assert-level=error
done
for repeat in 1 3 31; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" graphics_address_tb -gREPEATS="$repeat" --assert-level=error
done
# LEN counts raster lines with doubled lines too (Flame Zapper: 2 x rows), odd splits included
for length in 2 7 398; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" graphics_address_tb -gREPEATS=1 -gFIRST_LENGTH="$length" --assert-level=error
done
