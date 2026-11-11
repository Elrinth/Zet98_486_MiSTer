#!/usr/bin/env bash
# VSYNC interrupt through the master 8259 as wired in Zet98MiSTer.vhd (IR2 retractable).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" rtl/pc98_vsync_irq.vhd Zet98/z8259.vhd tests/vsync_pic_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" vsync_pic_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" vsync_pic_tb --assert-level=error
# Negative control: IR2 not retractable (B280) keeps the stale request.
if ghdl -r --std=08 -fsynopsys --workdir="$out" vsync_pic_tb -gRETRACT=01000000 --assert-level=error > "$out/old.log" 2>&1; then
    echo 'FAIL: non-retractable IR2 negative control passed'; exit 1
fi
grep -q 'stale VSYNC request fired when IRQ2 was unmasked' "$out/old.log" || { cat "$out/old.log"; exit 1; }
echo 'PASS: non-retractable IR2 negative control rejected (stale request at unmask)'
