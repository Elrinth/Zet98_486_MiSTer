#!/usr/bin/env bash
# Memory increment followed by a same-word reload (Watcom C 9.x loop tails;
# original PC-98 Doom's R_PrecacheLevel ran one sprite frame too many).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/z486_rmw_reload.asm -o "$out/rmw.bin"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
  -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
  -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
  --top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 \
  -GTRACE_LIMIT=0 -GWATCHDOG_NS=400000000 "${sources[@]}" \
  rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
  rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
  rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
cp rtl/vendor/z486/*.hex "$out/"
(cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/rmw.bin")
echo 'PASS: memory INC then same-word reload, low RAM and DDR frames, three tail spacings'
