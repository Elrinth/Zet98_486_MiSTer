#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
run() {
 ghdl -a --std=08 --workdir="$out" "$1" tests/pc98_vsync_irq_tb.vhd
 ghdl -e --std=08 --workdir="$out" pc98_vsync_irq_tb
 ghdl -r --std=08 --workdir="$out" pc98_vsync_irq_tb --assert-level=error
}
run rtl/pc98_vsync_irq.vhd
# Negative control: IRQ2 straight from the retrace (the old wiring) must fail.
tr -d '\r' < rtl/pc98_vsync_irq.vhd | sed 's/^\tirq<=active;/\tirq<=vrtc;/' > "$out/free.vhd"
! cmp -s <(tr -d '\r' < rtl/pc98_vsync_irq.vhd) "$out/free.vhd"
if run "$out/free.vhd" > "$out/neg.log" 2>&1; then echo 'FAIL free-running IRQ2 accepted'; exit 1; fi
grep -q 'without a port 64h write' "$out/neg.log" || { cat "$out/neg.log"; exit 1; }
echo 'PASS: free-running IRQ2 rejected'
# Negative control: no retry for an unacknowledged request (B280) must fail.
tr -d '\r' < rtl/pc98_vsync_irq.vhd | sed '/not taken during this retrace/,+3d' > "$out/noretry.vhd"
! cmp -s <(tr -d '\r' < rtl/pc98_vsync_irq.vhd) "$out/noretry.vhd"
if run "$out/noretry.vhd" > "$out/neg2.log" 2>&1; then echo 'FAIL no-retry IRQ2 accepted'; exit 1; fi
grep -q 'unacknowledged IRQ2 not raised again' "$out/neg2.log" || { cat "$out/neg2.log"; exit 1; }
echo 'PASS: no-retry IRQ2 rejected'
