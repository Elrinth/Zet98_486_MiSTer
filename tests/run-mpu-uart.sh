#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for mhz in 20 40 50 60 90 100; do
    verilator --binary --timing -Wno-fatal --top-module pc98_mpu_uart_tb \
        -GCLOCK_MHZ="$mhz" --Mdir "$out/obj$mhz" \
        rtl/midi/pc98_mpu_uart.sv tests/pc98_mpu_uart_tb.sv \
        > "$out/compile$mhz.log" 2>&1 || { cat "$out/compile$mhz.log"; exit 1; }
    "$out/obj$mhz/Vpc98_mpu_uart_tb"
done
# A held CPU strobe must have exactly one FIFO side effect. Verify the test
# fails if the write edge guard is removed; this caused prior peripheral bugs.
sed 's/io_write \&\& !previous_write/io_write/' rtl/midi/pc98_mpu_uart.sv > "$out/bad.sv"
verilator --binary --timing -Wno-fatal --top-module pc98_mpu_uart_tb \
    --Mdir "$out/bad" "$out/bad.sv" tests/pc98_mpu_uart_tb.sv \
    > "$out/bad-compile.log" 2>&1 || { cat "$out/bad-compile.log"; exit 1; }
if "$out/bad/Vpc98_mpu_uart_tb" > "$out/bad.log" 2>&1; then
    echo 'FAIL: held-write negative control passed'; exit 1
fi
grep -Eq 'UART ACK repeated|MIDI byte' "$out/bad.log" || { cat "$out/bad.log"; exit 1; }
echo 'PASS: held-write negative control rejected'
# UART reset must not manufacture an ACK or interrupt (Roland manual p22).
sed 's/ \&\& !uart_mode;$/;/' rtl/midi/pc98_mpu_uart.sv > "$out/reset-bad.sv"
verilator --binary --timing -Wno-fatal --top-module pc98_mpu_uart_tb \
    --Mdir "$out/reset-bad" "$out/reset-bad.sv" tests/pc98_mpu_uart_tb.sv \
    > "$out/reset-bad-compile.log" 2>&1 || { cat "$out/reset-bad-compile.log"; exit 1; }
if "$out/reset-bad/Vpc98_mpu_uart_tb" > "$out/reset-bad.log" 2>&1; then
    echo 'FAIL: UART reset ACK negative control passed'; exit 1
fi
grep -q 'UART reset falsely acknowledged' "$out/reset-bad.log" || { cat "$out/reset-bad.log"; exit 1; }
echo 'PASS: UART reset ACK negative control rejected'
