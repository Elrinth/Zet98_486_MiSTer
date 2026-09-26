#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" tests/lcell_model.vhd Zet98/sdramc.vhd tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
for sub in false true; do
 for mhz in 20 40 50 60 90 100; do
  for phase in 0 1300 4700 9100; do
   ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb -gCPU_MHZ="$mhz" -gMEM_PHASE_PS="$phase" -gUSE_SUB="$sub" -gBUFFERED=true -gHOLD_COMPLETION_CYCLES=8 --assert-level=error
  done
 done
done
for port in cpu sub; do
 sed "s/${port}end<=not ${port}end;/${port}end<='1';/" Zet98/sdramc.vhd > "$out/stale-$port.vhd"
 ghdl -a --std=08 -fsynopsys --workdir="$out" tests/lcell_model.vhd "$out/stale-$port.vhd" tests/sdram_request_tb.vhd
 ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
 sub=false; if [ "$port" = sub ]; then sub=true; fi
 if ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb -gCPU_MHZ=60 -gUSE_SUB="$sub" -gBUFFERED=true --assert-level=error > "$out/bad-$port.log" 2>&1; then
  echo "FAIL: stale $port completion accepted"; exit 1
 fi
 grep -q 'SDRAM request timed out' "$out/bad-$port.log"
 echo "PASS: stale $port completion rejected"
done
