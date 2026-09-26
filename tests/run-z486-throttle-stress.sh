#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -DREP_COUNT_TESTS=1 -DZ486_SHIFT_TESTS=1 -f bin tests/ao486_smoke.asm -o "$out/smoke.bin" -l "$out/smoke.lst"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
    -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
    --top-module ao486_cpu_tb "${sources[@]}" \
    rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
    rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv \
    rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
    rtl/cpu/z486_pc98_adapter.sv tests/ao486_cpu_tb.sv > "$out/compile.log" 2>&1 || {
        tail -n 100 "$out/compile.log"; exit 1;
    }
cp rtl/vendor/z486/*.hex "$out/"
cd "$out"
for mask in 255 4095; do
  for speed in 0 1 2 3; do
    ./obj/Vao486_cpu_tb "+program=$out/smoke.bin" +bus_seed=9821 +bus_wait_mask=$mask +speed=$speed +watchdog_ms=1000
  done
done
echo 'PASS: z486 all speeds with long bus response delays'
