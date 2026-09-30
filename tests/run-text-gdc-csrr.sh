#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
run() {
 ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" "$1" tests/text_gdc_csrr_tb.vhd
 ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" text_gdc_csrr_tb
 ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" text_gdc_csrr_tb --assert-level=error --ieee-asserts=disable-at-0
}
run Zet98/GDC/txtgdc.vhd
# Negative control: the old decoder only counted CSRR data after a parameter byte.
tr -d '\r' < Zet98/GDC/txtgdc.vhd | sed '/CSRR takes no parameters/,+1d' > "$out/old.vhd"
if run "$out/old.vhd" > "$out/negative.log" 2>&1; then
 echo 'FAIL CSRR without data accepted'; exit 1
fi
grep -q 'DATA READY never set' "$out/negative.log" || { cat "$out/negative.log"; exit 1; }
echo 'PASS old CSRR decoder rejected'
