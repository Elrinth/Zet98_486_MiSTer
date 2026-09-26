#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for mhz in 20 90 100; do
  verilator --binary --timing -Wno-fatal --top-module mpu_panic_tb -GCLOCK_MHZ=$mhz --Mdir "$out/obj$mhz" rtl/midi/pc98_mpu_uart.sv tests/mpu_panic_tb.sv > "$out/compile$mhz.log" 2>&1 || { cat "$out/compile$mhz.log"; exit 1; }
  "$out/obj$mhz/Vmpu_panic_tb"
done
bash tests/run-mpu-uart.sh
