#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/video_timing_pkg.vhd LIB/delayer.vhd VIDEO/text_row_counter.vhd Zet98/knjaddrcnv.vhd VIDEO/font_prefetch.vhd VIDEO/knjscr.vhd tests/text_gaiji_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" text_gaiji_tb
for delay in 0 12 25; do
 ghdl -r --std=08 -fsynopsys --workdir="$out" text_gaiji_tb -gRAM_DELAY_NS="$delay" --assert-level=error --ieee-asserts=disable-at-0
done
