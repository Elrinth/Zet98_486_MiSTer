#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
run() {
 ghdl -a --std=08 --workdir="$out" "$1" tests/pc98_display_page_tb.vhd
 ghdl -e --std=08 --workdir="$out" pc98_display_page_tb
 ghdl -r --std=08 --workdir="$out" pc98_display_page_tb --assert-level=error
}
run rtl/pc98_display_page.vhd
# Negative control: the old latch (retrace end only) must fail the Touhou case.
tr -d '\r' < rtl/pc98_display_page.vhd | sed 's/elsif(disp\/=shown and draw=shown)then/elsif(false)then/' > "$out/old.vhd"
! cmp -s <(tr -d '\r' < rtl/pc98_display_page.vhd) "$out/old.vhd"
if run "$out/old.vhd" > "$out/neg.log" 2>&1; then echo 'FAIL retrace-only latch accepted'; exit 1; fi
grep -q 'did not apply the pending flip' "$out/neg.log" || { cat "$out/neg.log"; exit 1; }
echo 'PASS: retrace-only latch rejected'
