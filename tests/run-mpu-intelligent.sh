#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
build() {
    verilator --binary --timing -Wno-fatal --top-module pc98_mpu_intelligent_tb \
        --Mdir "$out/$2" "$1" tests/pc98_mpu_intelligent_tb.sv > "$out/$2.log" 2>&1 || { cat "$out/$2.log"; exit 1; }
}
build rtl/midi/pc98_mpu_uart.sv new
"$out/new/Vpc98_mpu_intelligent_tb"
# Negative control: the UART-only MPU never ACKed intelligent commands.
tr -d '\r' < rtl/midi/pc98_mpu_uart.sv | sed 's/if (command_write \&\& !uart_mode) begin/if (command_write \&\& !uart_mode \&\& io_writedata[7:0] == 8'"'"'h3f) begin/' > "$out/old.sv"
! cmp -s <(tr -d '\r' < rtl/midi/pc98_mpu_uart.sv) "$out/old.sv"
build "$out/old.sv" old
if "$out/old/Vpc98_mpu_intelligent_tb" > "$out/old.txt" 2>&1; then echo 'FAIL: UART-only MPU accepted'; exit 1; fi
grep -q 'not ACKed' "$out/old.txt" || { cat "$out/old.txt"; exit 1; }
echo 'PASS: UART-only MPU (no intelligent ACK) rejected'
