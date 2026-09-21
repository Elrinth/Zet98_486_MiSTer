#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for bench in floppy_caption_tb floppy_overlay_tb floppy_overlay_stream_tb; do
    iverilog -g2012 -Wall -s "$bench" -o "$out/overlay.vvp" rtl/floppy_overlay.sv "tests/$bench.sv"
    vvp "$out/overlay.vvp"
done
# One wrong table remainder must be detected by the exhaustive coordinate test.
sed "s/6'd21: caption_div3=6'h1c;/6'd21: caption_div3=6'h1d;/" rtl/floppy_overlay.sv > "$out/bad.sv"
iverilog -g2012 -Wall -s floppy_caption_tb -o "$out/bad.vvp" "$out/bad.sv" tests/floppy_caption_tb.sv
if vvp "$out/bad.vvp" > "$out/bad.log" 2>&1; then
    echo 'FAIL: incorrect caption table accepted';exit 1
fi
grep -q 'caption coordinate mismatch' "$out/bad.log" || { cat "$out/bad.log";exit 1; }
echo 'PASS: incorrect caption table negative control rejected'
