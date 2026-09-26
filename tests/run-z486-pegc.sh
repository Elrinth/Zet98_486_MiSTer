#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/pegc_cpu_probe.asm -o "$out/pegc.bin"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 1 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
    -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
    --top-module z486_xms_resident_tb -GRAM_MB=64 -GPEGC_ENABLE=1 -GTRACE_LIMIT=0 \
    "${sources[@]}" rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_bus_bridge.sv \
    rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv rtl/cpu/z486_pc98_adapter.sv \
    rtl/graphics/pc98_pegc_bus.sv rtl/graphics/pc98_pegc_control.sv rtl/graphics/pc98_pegc_palette.sv \
    rtl/graphics/pc98_pegc_memory.sv rtl/graphics/pc98_pegc_ddr_arbiter.sv \
    tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 70 "$out/compile.log";exit 1; }
cp rtl/vendor/z486/*.hex "$out/"
(cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/pegc.bin")
echo 'PASS: actual z486 PEGC palette, banked/linear aliases, unaligned writes and ordinary RAM isolation'
# The exact same enabled wrapper must still execute the previous protected-mode
# RAM/stack regression through the new arbiter.
nasm -f bin tests/hardware/stack_allocation_probe.asm -o "$out/stack.bin"
(cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/stack.bin")
echo 'PASS: protected-mode stack/RAM regression with PEGC arbiter enabled'
