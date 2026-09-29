#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -DCPU_TEST=1 -DLDT_TEST=1 -f bin tests/hardware/pit_pm_irq_probe.asm -o "$out/cs.bin"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
-Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
-Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
--top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 -GPIT_PM_TEST=1 -GTRACE_LIMIT=160 "${sources[@]}" \
rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 80 "$out/compile.log"; exit 1; }
cp rtl/vendor/z486/*.hex "$out/"
(cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/cs.bin")
echo 'PASS: actual CPU LDT protected-mode IRQ and IRETD control'
