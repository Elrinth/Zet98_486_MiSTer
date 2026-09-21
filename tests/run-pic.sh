#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/z8259.vhd tests/pc98_pic_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" pc98_pic_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" pc98_pic_tb --assert-level=error
if ghdl -r --std=08 -fsynopsys --workdir="$out" pc98_pic_tb \
    -gRETRACT_MIDI=false --assert-level=error > "$out/old.log" 2>&1; then
    echo 'FAIL: retained MIDI request negative control passed'; exit 1
fi
grep -q 'withdrawn MIDI IRQ remained pending' "$out/old.log" || { cat "$out/old.log"; exit 1; }
echo 'PASS: retained MIDI request negative control rejected'
