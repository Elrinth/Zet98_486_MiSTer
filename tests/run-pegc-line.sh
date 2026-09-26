#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for half in 5000 5556; do
    for phase in 1300 4700 9100; do
        iverilog -g2012 -Wall -s pc98_pegc_line_fetch_tb \
            -Ppc98_pegc_line_fetch_tb.CPU_HALF_PS="$half" -Ppc98_pegc_line_fetch_tb.VIDEO_PHASE_PS="$phase" \
            -o "$out/line" rtl/graphics/pc98_pegc_line_fetch.sv rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/pc98_pegc_line_fetch_tb.sv
        vvp "$out/line"
    done
done
sed 's/current_request && !line_start && !active_started && !active && line_enable/line_enable/' \
    rtl/graphics/pc98_pegc_line_fetch.sv > "$out/broken.sv"
iverilog -g2012 -s pc98_pegc_line_fetch_tb -o "$out/negative" "$out/broken.sv" rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/pc98_pegc_line_fetch_tb.sv
if vvp "$out/negative" > "$out/negative.log" 2>&1; then
    echo 'FAIL: stale/late line publication accepted';exit 1
fi
grep -Eq 'pixel validity/deadline alignment|packed pixel order/stale line' "$out/negative.log" || { cat "$out/negative.log";exit 1; }
echo 'PASS: stale/late line publication negative control rejected'
# Held command payload arrives before the synchronized request is acted on.
sed 's/wire \[17:0\] request_transfer = request_payload;/wire [17:0] request_transfer; assign #20 request_transfer = request_payload;/' \
    rtl/graphics/pc98_pegc_line_fetch.sv > "$out/delayed.sv"
iverilog -g2012 -s pc98_pegc_line_fetch_tb -o "$out/delayed" "$out/delayed.sv" rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/pc98_pegc_line_fetch_tb.sv
vvp "$out/delayed"
sed 's/assign #20/assign #100/' "$out/delayed.sv" > "$out/late.sv"
iverilog -g2012 -s pc98_pegc_line_fetch_tb -o "$out/late" "$out/late.sv" rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/pc98_pegc_line_fetch_tb.sv
if vvp "$out/late" > "$out/late.log" 2>&1; then
    echo 'FAIL: late line request payload accepted';exit 1
fi
grep -q 'packed pixel order/stale line' "$out/late.log" || { cat "$out/late.log";exit 1; }
echo 'PASS: late request payload negative control rejected'
# Raw CPU/video readiness must not directly release pixel asynchronous clears.
sed 's/wire cpu_reset=cpu_reset_sync\[1\], video_reset=video_reset_sync\[1\];/wire cpu_reset=reset, video_reset=reset;/' \
    rtl/graphics/pc98_pegc_line_fetch.sv > "$out/raw-reset.sv"
iverilog -g2012 -s pc98_pegc_line_fetch_tb -o "$out/raw-reset" "$out/raw-reset.sv" rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/pc98_pegc_line_fetch_tb.sv
if vvp "$out/raw-reset" > "$out/raw-reset.log" 2>&1; then
    echo 'FAIL: unsynchronized reset release accepted';exit 1
fi
grep -q 'reset released before two local edges' "$out/raw-reset.log"
echo 'PASS: unsynchronized reset release rejected'
