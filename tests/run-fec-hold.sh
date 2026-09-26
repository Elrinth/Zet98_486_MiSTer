#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 tests/instrument_fec_hold.py "$out/held.vhd" "$out/early.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/held.vhd" tests/floppy_sdram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb
for reads in false true; do
 for continuous in false true; do
  for mhz in 20 40 50 60 90 100; do
   for phase in 0 417 833 1250 1667 2083 2500 2917 3333 3750 4167 4583 5000 5417 5833 6250 6667 7083 7500 7917 8333 8750 9167 9583; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb -gUSE_FEC=true -gCPU_MHZ="$mhz" -gMEM_PHASE_PS="$phase" -gCONTINUOUS="$continuous" -gALL_READS="$reads" --assert-level=error --ieee-asserts=disable-at-0
   done
  done
 done
done
ghdl -a --std=08 -fsynopsys --workdir="$out" "$out/early.vhd" tests/floppy_sdram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out" floppy_sdram_tb -gUSE_FEC=true -gCPU_MHZ=100 -gALL_READS=true -gCONTINUOUS=true --assert-level=error > "$out/bad.log" 2>&1; then
 echo 'FAIL: early FEC payload release accepted'; exit 1
fi
grep -q 'FEC payload changed inside post-capture hold window' "$out/bad.log" || { cat "$out/bad.log";exit 1; }
echo 'PASS: actual FEC payload post-capture hold and early-release negative control'
