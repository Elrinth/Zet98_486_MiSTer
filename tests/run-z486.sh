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
./obj/Vao486_cpu_tb "+program=$out/smoke.bin" || { tail -n 100 "$out/smoke.lst"; exit 1; }
./obj/Vao486_cpu_tb "+program=$out/smoke.bin" +bus_seed=9821
for speed in 1 2 3; do
    ./obj/Vao486_cpu_tb "+program=$out/smoke.bin" +bus_seed=9821 +speed=$speed
done
./obj/Vao486_cpu_tb "+program=$out/smoke.bin" +bus_seed=472 +switch_speed
echo 'PASS: z486 backend through real PC-98 memory/I/O bridges and retained smoke program'
cd "$root"
for test in cache extmem; do
    params=()
    asm_flags=()
    if [ "$test" = extmem ]; then params+=(-GRAM_MB=64); asm_flags+=(-DTOP_MB=64 -DSIM=1); fi
    nasm "${asm_flags[@]}" -f bin "tests/ao486_${test}.asm" -o "$out/$test.bin"
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
        -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/$test-cpu" \
        --top-module "ao486_${test}_tb" "${params[@]}" "${sources[@]}" \
        rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
        rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv \
        rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
        rtl/cpu/z486_pc98_adapter.sv "tests/ao486_${test}_tb.sv" > "$out/$test-compile.log" 2>&1 || {
            tail -n 100 "$out/$test-compile.log"; exit 1;
        }
    (cd "$out"; "./$test-cpu/Vao486_${test}_tb" "+program=$out/$test.bin")
done
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -Irtl/vendor/z486 --Mdir "$out/cache" \
    --top-module z486_pc98_cache_tb rtl/vendor/z486/memory.sv \
    rtl/vendor/z486/l1_cache.sv rtl/vendor/z486/l1_icache.sv \
    tests/z486_pc98_cache_tb.sv > "$out/cache-compile.log" 2>&1 || {
        tail -n 100 "$out/cache-compile.log"; exit 1;
    }
"$out/cache/Vz486_pc98_cache_tb"

iverilog -g2012 -s pc98_debug_uart_tb -o "$out/uart.vvp" rtl/cpu/pc98_debug_uart.sv tests/pc98_debug_uart_tb.sv
vvp "$out/uart.vvp"
