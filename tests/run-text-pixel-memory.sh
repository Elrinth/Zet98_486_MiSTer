#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/video_timing_pkg.vhd \
    LIB/delayer.vhd VIDEO/text_row_counter.vhd Zet98/knjaddrcnv.vhd \
    VIDEO/knjscr.vhd tests/text_pixel_memory_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" text_pixel_memory_tb
for delay in 0 12 25; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" text_pixel_memory_tb -gRAM_DELAY_NS="$delay" --assert-level=error
    ghdl -r --std=08 -fsynopsys --workdir="$out" text_pixel_memory_tb -gRAM_DELAY_NS="$delay" -gCURSOR_TEST=true --assert-level=error
done
# Model a memory that misses the pixel pipeline deadline: checking only the
# address stream would miss this, so require a rendered-pixel failure.
if ghdl -r --std=08 -fsynopsys --workdir="$out" text_pixel_memory_tb -gRAM_DELAY_NS=200 --assert-level=error > "$out/negative.log" 2>&1; then
    echo 'FAIL: text checker accepted data beyond the pixel pipeline deadline' >&2
    exit 1
fi
grep -q 'Wrong text pixel' "$out/negative.log"
echo 'PASS: late text/font data negative control rejected'
