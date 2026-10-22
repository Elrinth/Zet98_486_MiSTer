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
# The B266 PIC answered a request masked before INTA with vector 0 (INT 08h).
if [ -n "${B266_PIC:-}" ]; then cp "$B266_PIC" "$out/z8259_b266.vhd"; else git show B266:Zet98/z8259.vhd > "$out/z8259_b266.vhd"; fi
mkdir -p "$out/old"
ghdl -a --std=08 -fsynopsys --workdir="$out/old" "$out/z8259_b266.vhd" tests/pc98_pic_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out/old" pc98_pic_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out/old" pc98_pic_tb --assert-level=error > "$out/b266.log" 2>&1; then
    echo 'FAIL: B266 PIC (vector 0 for a masked request) negative control passed'; exit 1
fi
grep -q 'masked master request did not give the default IR7 vector 17h' "$out/b266.log" || { cat "$out/b266.log"; exit 1; }
echo 'PASS: B266 PIC negative control rejected (masked request delivered as INT 08h)'
