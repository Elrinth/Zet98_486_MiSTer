#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 tests/extract_video_status.py "$out/actual.sv"
for half in 25000 12500 10000 8333 5556 5000; do
    iverilog -g2012 -s video_status_tb -Pvideo_status_tb.HALF_PERIOD=$half \
        -o "$out/status" "$out/actual.sv" tests/video_status_tb.sv
    vvp "$out/status"
done
sed 's/hdmi_vs_sync <= hdmi_vs_meta;/hdmi_vs_sync <= HDMI_TX_VS;/' "$out/actual.sv" > "$out/bad.sv"
iverilog -g2012 -s video_status_tb -o "$out/bad" "$out/bad.sv" tests/video_status_tb.sv
if vvp "$out/bad" > "$out/bad.log" 2>&1; then
    echo 'FAIL: video first-stage bypass accepted'; exit 1
fi
grep -q 'video status bypassed synchronization' "$out/bad.log"
echo 'PASS: video first-stage bypass rejected'
