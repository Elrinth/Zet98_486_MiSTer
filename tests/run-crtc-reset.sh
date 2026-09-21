#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# Only rename the legacy VMODE identifier (reserved in VHDL-2008).
# VHDL-2008 is needed for expression actuals elsewhere in the original core.
sed 's/\<VMODE\>/VMODE_LEGACY/g' VIDEO/textscr.vhd > "$out/textscr.vhd"
sed 's/\<VMODE\>/VMODE_LEGACY/g' VIDEO/CRTC98.vhd > "$out/CRTC98.vhd"
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" VIDEO/video_timing_pkg.vhd rtl/reset_release.vhd \
    LIB/delayer.vhd VIDEO/VTIMING.vhd VIDEO/text_row_counter.vhd Zet98/knjaddrcnv.vhd \
    VIDEO/knjscr.vhd "$out/textscr.vhd" VIDEO/GRAPHSCR98.vhd VIDEO/synccont2.vhd \
    "$out/CRTC98.vhd" tests/crtc_reset_render_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" crtc_reset_render_tb
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" crtc_reset_render_tb --assert-level=error --ieee-asserts=disable-at-0
