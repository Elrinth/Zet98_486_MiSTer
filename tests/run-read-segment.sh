#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sed 's/module read_segment(/module read_segment_legacy(/' tests/reference/read_segment_legacy.v > "$out/legacy.v"
iverilog -g2012 -I rtl/vendor/ao486 -s read_segment_tb -o "$out/test" rtl/vendor/ao486/pipeline/read_segment.v "$out/legacy.v" tests/read_segment_tb.sv
vvp "$out/test"
sed 's/available < {1.b0, length}/available <= {1\x27b0, length}/' rtl/vendor/ao486/pipeline/read_segment.v > "$out/bad-limit.v"
iverilog -g2012 -I rtl/vendor/ao486 -s read_segment_tb -o "$out/negative" "$out/bad-limit.v" "$out/legacy.v" tests/read_segment_tb.sv
if vvp "$out/negative" > "$out/negative.log" 2>&1; then
    echo 'FAIL: off-by-one segment limit accepted';exit 1
fi
grep -q 'segment differs' "$out/negative.log"
echo 'PASS: off-by-one segment limit rejected'
