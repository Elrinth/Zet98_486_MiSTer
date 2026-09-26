#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sed "s/8'd120/8'd119/" rtl/midi/pc98_mpu_uart.sv > "$out/bad.sv"
verilator --binary --timing -Wno-fatal --top-module mpu_panic_tb --Mdir "$out/obj" "$out/bad.sv" tests/mpu_panic_tb.sv > "$out/compile.log" 2>&1 || { cat "$out/compile.log"; exit 1; }
if "$out/obj/Vmpu_panic_tb" > "$out/run.log" 2>&1; then echo 'FAIL: wrong silence controller accepted';exit 1;fi
grep -q 'panic wire byte' "$out/run.log" || { cat "$out/run.log";exit 1; }
echo 'PASS: wrong All Sound Off controller rejected by independent serial decoder'
bash tests/run-disk-interface.sh
