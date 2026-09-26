#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for bench in floppy_caption_tb floppy_overlay_tb floppy_overlay_stream_tb; do
    iverilog -g2012 -Wall -s "$bench" -o "$out/overlay.vvp" rtl/floppy_overlay.sv "tests/$bench.sv"
    vvp "$out/overlay.vvp"
done
# Negative controls must reject the original placement, opaque background,
# and a miswired bit order in the existing boot font.
for variant in old_position opaque wrong_font; do
    case "$variant" in
      old_position) sed "s/bottom_edge-12'd90/bottom_edge-12'd74/;s/bottom_edge-12'd20/bottom_edge-12'd4/" rtl/floppy_overlay.sv > "$out/bad.sv" ;;
      opaque) sed "s/else {out_r,out_g,out_b}<=rgb_pipe2;/else {out_r,out_g,out_b}<=0;/" rtl/floppy_overlay.sv > "$out/bad.sv" ;;
      wrong_font) sed "s/font_row\[3'd7-text_column\]/font_row[text_column]/" rtl/floppy_overlay.sv > "$out/bad.sv" ;;
    esac
    iverilog -g2012 -Wall -s floppy_overlay_tb -o "$out/bad.vvp" "$out/bad.sv" tests/floppy_overlay_tb.sv
    if vvp "$out/bad.vvp" > "$out/bad.log" 2>&1; then
        echo "FAIL: $variant accepted";exit 1
    fi
    grep -Eq 'overlay pixel mismatch|overlay outside' "$out/bad.log" || { cat "$out/bad.log";exit 1; }
    echo "PASS: $variant negative control rejected"
done
