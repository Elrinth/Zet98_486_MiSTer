#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for half in 5000 5556 8333 16667; do
    for phase in 1300 4700 9100; do
        iverilog -g2012 -Wall -s pc98_pegc_palette_tb \
            -Ppc98_pegc_palette_tb.CPU_HALF_PS="$half" -Ppc98_pegc_palette_tb.VIDEO_PHASE_PS="$phase" \
            -o "$out/palette" rtl/graphics/pc98_pegc_palette.sv tests/pc98_pegc_palette_tb.sv
        vvp "$out/palette"
    done
done
sed 's/\[video_index\]/[video_index[3:0]]/g' rtl/graphics/pc98_pegc_palette.sv > "$out/broken.sv"
iverilog -g2012 -s pc98_pegc_palette_tb -o "$out/negative" "$out/broken.sv" tests/pc98_pegc_palette_tb.sv
if vvp "$out/negative" > "$out/negative.log" 2>&1; then
    echo 'FAIL: 16-entry lookup accepted';exit 1
fi
grep -q 'video RGB888/index' "$out/negative.log" || { cat "$out/negative.log";exit 1; }
echo 'PASS: truncated video lookup negative control rejected'
