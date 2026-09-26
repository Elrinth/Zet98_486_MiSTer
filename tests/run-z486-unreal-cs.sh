#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/unreal_cs_probe.asm -o "$out/cs.bin"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
-Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
-Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
--top-module z486_xms_resident_tb -GRAM_MB=64 "${sources[@]}" \
rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_bus_bridge.sv \
rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 80 "$out/compile.log"; exit 1; }
cp rtl/vendor/z486/*.hex "$out/"
(cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/cs.bin")
echo 'PASS: all four real-mode CS low-bit values survive CR0 mode changes; CPL0 instructions and protected far CS reload pass'
