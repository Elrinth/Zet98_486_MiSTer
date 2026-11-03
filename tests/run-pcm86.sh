#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for test in pcm86_tb pcm86_rates_tb pcm86_driver_refill_tb pcm86_win95_tb pcm86_u8_tb; do
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
# Negative control: without low_fire (the interrupt after a burst that leaves
# the level at or below the threshold) Ultima VIII's speech refill never interrupts.
tr -d '\r' < rtl/pcm86.sv | sed 's/wire low_fire = low_arm \&\&/wire low_fire = 1'"'"'b0 \&\& low_arm \&\&/' > "$out/noburst.sv"
if cmp -s <(tr -d '\r' < rtl/pcm86.sv) "$out/noburst.sv"; then echo 'FAIL: low_fire negative control did not apply'; exit 1; fi
iverilog -g2012 -Wall -s pcm86_u8_tb -o "$out/noburst.vvp" "$out/noburst.sv" tests/pcm86_u8_tb.sv
if vvp "$out/noburst.vvp" > "$out/noburst.txt" 2>&1 && ! grep -q FATAL "$out/noburst.txt"; then cat "$out/noburst.txt"; echo 'FAIL: below-threshold refill without interrupt accepted'; exit 1; fi
grep -q 'below-threshold refill' "$out/noburst.txt" || { cat "$out/noburst.txt"; exit 1; }
echo 'PASS: below-threshold refill without interrupt (Ultima VIII speech stall) rejected'
