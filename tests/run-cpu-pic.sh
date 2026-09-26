#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -s tests/pic_generated.v
sha256sum tests/pic_generated.v
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 tests/make_cpu_pic_tb.py "$out/cpu_pic_tb.sv"
nasm -f bin tests/cpu_pic_probe.asm -o "$out/probe.bin"
nasm -DCASCADE=1 -f bin tests/cpu_pic_probe.asm -o "$out/cascade.bin"
nasm -DCASCADE=1 -DBIOSMODE=1 -f bin tests/cpu_pic_probe.asm -o "$out/bootmode.bin"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 1 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
 -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
 -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
 --top-module ao486_cpu_tb "${sources[@]}" \
 rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_bus_bridge.sv \
 rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
 rtl/cpu/z486_pc98_adapter.sv tests/pic_generated.v "$out/cpu_pic_tb.sv" \
 > "$out/compile.log" 2>&1 || { tail -n 80 "$out/compile.log"; exit 1; }
cp rtl/vendor/z486/*.hex "$out/"
if [ "${CPU_PIC_MODE:-all}" != boot ]; then
(cd "$out"; ./obj/Vao486_cpu_tb "+program=$out/probe.bin")
(cd "$out"; ./obj/Vao486_cpu_tb "+program=$out/probe.bin" +bus_seed=9821)
(cd "$out"; ./obj/Vao486_cpu_tb "+program=$out/cascade.bin" +expected_irqs=15)
(cd "$out"; ./obj/Vao486_cpu_tb "+program=$out/cascade.bin" +expected_irqs=15 +bus_seed=9821)
fi
(cd "$out"; ./obj/Vao486_cpu_tb "+program=$out/bootmode.bin" +expected_irqs=15)
(cd "$out"; ./obj/Vao486_cpu_tb "+program=$out/bootmode.bin" +expected_irqs=15 +bus_seed=9821)
