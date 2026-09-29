#!/usr/bin/env bash
# INT 1Fh AH=90h block move from the resident disk-ROM code on the actual z486.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin software/pc98_ide_resident.asm -o "$out/resident.bin"
nasm -f bin -DRESIDENT="\"$out/resident.bin\"" tests/hardware/int1f_move.asm -o "$out/t.bin"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
  -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
  -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
  --top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 \
  -GTRACE_LIMIT=0 -GWATCHDOG_NS=40000000 "${sources[@]}" \
  rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
  rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
  rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
cp rtl/vendor/z486/*.hex "$out/"
if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/run.log" 2>&1; then
  grep -v '^XMS EIP' "$out/run.log" | tail -n 8; exit 1
fi
echo 'PASS: INT 1Fh AH=90h block move (resident ROM): conventional <-> 200000h, A20 restored, limit error CF'
