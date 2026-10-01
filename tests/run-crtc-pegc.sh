#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sed 's/\<VMODE\>/VMODE_LEGACY/g' VIDEO/textscr.vhd > "$out/textscr.vhd"
sed 's/\<VMODE\>/VMODE_LEGACY/g' VIDEO/CRTC98.vhd > "$out/CRTC98.vhd"
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" VIDEO/video_timing_pkg.vhd rtl/reset_release.vhd \
    LIB/delayer.vhd VIDEO/VTIMING.vhd VIDEO/text_row_counter.vhd Zet98/knjaddrcnv.vhd \
    VIDEO/font_prefetch.vhd VIDEO/knjscr.vhd "$out/textscr.vhd" VIDEO/GRAPHSCR98.vhd VIDEO/synccont2.vhd VIDEO/pegc_raster.vhd \
    "$out/CRTC98.vhd" tests/crtc_reset_render_tb.vhd tests/crtc_pegc_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" crtc_pegc_tb
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" crtc_pegc_tb --assert-level=error --ieee-asserts=disable-at-0
# Remove one of the required alignment clocks: exact first/last pixels must fail.
sed 's/pc_rgb_delay(5)(/pc_rgb_delay(4)(/g' "$out/CRTC98.vhd" > "$out/broken.vhd"
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" "$out/broken.vhd" tests/crtc_pegc_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" crtc_pegc_tb
if ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" crtc_pegc_tb --assert-level=error --ieee-asserts=disable-at-0 > "$out/negative.log" 2>&1; then
    echo 'FAIL: misaligned packed RGB accepted';exit 1
fi
grep -q 'packed RGB/DE latency or channel mismatch' "$out/negative.log"
echo 'PASS: misaligned packed RGB rejected'
bash tests/run-crtc-reset.sh
bash tests/run-video-settings.sh
