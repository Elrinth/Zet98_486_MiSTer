#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sources=(rtl/graphics/pc98_pegc_{control,palette,memory,bus,ddr_arbiter,line_fetch}.sv tests/pc98_pegc_display_tb.sv)
for pair in '5556 1300' '5000 9100'; do
    read -r half phase <<< "$pair"
    iverilog -g2012 -Wall -s pc98_pegc_display_tb -Ppc98_pegc_display_tb.CPU_HALF_PS="$half" \
        -Ppc98_pegc_display_tb.VIDEO_PHASE_PS="$phase" -o "$out/display" "${sources[@]}"
    vvp "$out/display"
done
# A four-bit palette address must fail even though the framebuffer is intact.
sed 's/\.video_index(video_index)/.video_index({4\x27b0,video_index[3:0]})/' rtl/graphics/pc98_pegc_bus.sv > "$out/broken.sv"
iverilog -g2012 -s pc98_pegc_display_tb -o "$out/negative" "$out/broken.sv" \
    rtl/graphics/pc98_pegc_{control,palette,memory,ddr_arbiter,line_fetch}.sv tests/pc98_pegc_display_tb.sv
if vvp "$out/negative" > "$out/negative.log" 2>&1; then
    echo 'FAIL: truncated framebuffer palette address accepted';exit 1
fi
grep -q 'CPU-written framebuffer/palette RGB mismatch' "$out/negative.log"
echo 'PASS: truncated palette in complete display path rejected'
