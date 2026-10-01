#!/usr/bin/env bash
# Kanji/ANK font from SDRAM through the row-ahead prefetch must render the
# same pixels as the renderer reading the font block RAM directly. The
# negative control returns a wrong byte from the SDRAM font model.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/video_timing_pkg.vhd \
    LIB/delayer.vhd VIDEO/text_row_counter.vhd Zet98/knjaddrcnv.vhd \
    VIDEO/font_prefetch.vhd VIDEO/knjscr.vhd tests/font_prefetch_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" font_prefetch_tb
for args in "-gSEED=1" "-gSEED=2 -gVLINES=19" "-gSEED=3 -gVLINES=7 -gMAXDELAY=30" "-gSEED=4 -gPITCHV=160"; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" font_prefetch_tb $args --assert-level=error
done
if ghdl -r --std=08 -fsynopsys --workdir="$out" font_prefetch_tb -gBREAK_FONT=true -gFRAMES=2 --assert-level=error > "$out/neg.log" 2>&1; then
    echo 'FAIL: wrong SDRAM font data was accepted' >&2; exit 1
fi
grep -q 'Prefetched text differs' "$out/neg.log" || { cat "$out/neg.log"; exit 1; }
echo 'PASS: wrong font data negative control rejected'
