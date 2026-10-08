#!/usr/bin/env bash
# Win95 Setup SYSDETMG.DLL ring-0 port I/O path on the actual z486: ring 3
# rewrites an LDT descriptor DPL, builds a 286 call gate and calls through it.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin ${CALL_GATE_DEFINES--DFLAT_SS0 -DTARGET_RPL3} tests/hardware/pm16_call_gate.asm -o "$out/csc.bin"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
  -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
  -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
  --top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 \
  -GTRACE_LIMIT=0 -GWATCHDOG_NS=20000000 "${sources[@]}" \
  rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
  rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
  rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
cp rtl/vendor/z486/*.hex "$out/"
if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/csc.bin") > "$out/run.log" 2>&1; then
  grep -v -e '^XMS EIP' "$out/run.log" | tail -n 20
  exit 1
fi
grep -E 'PASS|FAIL|fatal' "$out/run.log" | tail -3
echo "PASS: z486 ring-3 to ring-0 286 call gate (${CALL_GATE_DEFINES--DFLAT_SS0 -DTARGET_RPL3}) with six parameter words and RETF 12, after DPL rewrite, 100 rounds"
