#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 tests/make_pm_payload_cpu.py "$out/probe.asm"
nasm -f bin "$out/probe.asm" -o "$out/cs.bin"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
  -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
  -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
  --top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 -GPM_PAYLOAD_TEST=1 \
  -GTRACE_LIMIT=0 -GWATCHDOG_NS=200000000 "${sources[@]}" \
  rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_bus_bridge.sv \
  rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
  rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
cp rtl/vendor/z486/*.hex "$out/"
(cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/cs.bin")
echo 'PASS: actual CPU protected CRC windows, unaligned/2MB boundary/above16MB/near64MB, chained CRC and non-present descriptor exception restoration'
# The independent checksum must reject a broken CRC table polynomial.
sed 's/0edb88320h/0edb88321h/' "$out/probe.asm" > "$out/negative.asm"
nasm -f bin "$out/negative.asm" -o "$out/negative.bin"
if (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/negative.bin") > "$out/negative.log" 2>&1; then
  echo 'FAIL: corrupted CRC table passed'; exit 1
fi
grep -q 'protected-mode extended memory program failed' "$out/negative.log"
echo 'PASS: wrong CRC table negative rejected'
