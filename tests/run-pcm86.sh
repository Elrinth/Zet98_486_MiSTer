#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for test in pcm86_tb pcm86_rates_tb pcm86_driver_refill_tb pcm86_win95_tb; do
    iverilog -g2012 -Wall -s "$test" -o "$out/test.vvp" rtl/pcm86.sv "tests/$test.sv"
    vvp "$out/test.vvp"
done
# Negative control: the IRQ pin following the status bit (the request that
# returns while the FIFO is low) gives Windows 95 a second interrupt with
# the FIFO refilled.
tr -d '\r' < rtl/pcm86.sv | sed 's/assign irq = irq_line \&\& control\[5\] \&\& irq_gap==0;/assign irq = irq_pending \&\& control[5];/' > "$out/old.sv"
! cmp -s <(tr -d '\r' < rtl/pcm86.sv) "$out/old.sv"
iverilog -g2012 -Wall -s pcm86_win95_tb -o "$out/old.vvp" "$out/old.sv" tests/pcm86_win95_tb.sv
if vvp "$out/old.vvp" > "$out/old.txt" 2>&1 && ! grep -q FATAL "$out/old.txt"; then cat "$out/old.txt"; echo 'FAIL: level-only PCM request accepted'; exit 1; fi
grep -q 'FIFO refilled' "$out/old.txt" || { cat "$out/old.txt"; exit 1; }
echo 'PASS: level-only PCM request (spurious Windows 95 interrupt) rejected'
