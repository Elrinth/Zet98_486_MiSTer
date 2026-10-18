#!/usr/bin/env bash
# MPU-PC98II intelligent-mode sequencer (Arsys NMD, Star Cruiser II):
# tests/pc98_mpu_seq_tb.sv. Negative control: the MPU without the sequencer
# (tests/mpu_noseq.sv, the B256 module) never requests data.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
build() {
    verilator --binary --timing -Wno-fatal --top-module pc98_mpu_seq_tb \
        --Mdir "$out/$2" "$1" tests/pc98_mpu_seq_tb.sv > "$out/$2.log" 2>&1 || { cat "$out/$2.log"; exit 1; }
}
build rtl/midi/pc98_mpu_uart.sv new
"$out/new/Vpc98_mpu_seq_tb"
build tests/mpu_noseq.sv old
if "$out/old/Vpc98_mpu_seq_tb" > "$out/old.txt" 2>&1; then echo 'FAIL: MPU without sequencer accepted'; exit 1; fi
grep -q 'no request from the MPU' "$out/old.txt" || { cat "$out/old.txt"; exit 1; }
echo 'PASS: MPU without sequencer (no F9/F0 requests) rejected'
