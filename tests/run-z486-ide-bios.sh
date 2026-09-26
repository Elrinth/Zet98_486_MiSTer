#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
cp rtl/vendor/z486/*.hex "$out/"
for mode in read write; do
    if [[ "$mode" == read ]]; then
        source=tests/pc98_ide_bios.asm
        flags=(-DBIOS_SHORT_TEST=1)
        params=(-GEXPECT_READS=7)
    else
        source=tests/pc98_ide_write_bios.asm
        flags=(-DBIOS_WRITE_SMOKE=1)
        params=(-GEXPECT_READS=3 -GEXPECT_WRITES=3 -GWRITE_TEST=1)
    fi
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
        -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/$mode" \
        --top-module pc98_ide_bios_tb "${params[@]}" "${sources[@]}" \
        rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
        rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv \
        rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
        rtl/cpu/z486_pc98_adapter.sv tests/pc98_ide_bios_tb.sv \
        > "$out/$mode-compile.log" 2>&1 || { tail -n 100 "$out/$mode-compile.log"; exit 1; }
    for stack in cached uncached; do
        stack_flags=()
        if [[ "$stack" == uncached ]]; then stack_flags=(-DBIOS_HIGH_STACK=1); fi
        nasm "${flags[@]}" "${stack_flags[@]}" -f bin "$source" -o "$out/$mode-$stack.bin"
        echo "z486 real BIOS $mode, $stack bounce-buffer stack"
        (cd "$out"; "./$mode/Vpc98_ide_bios_tb" "+program=$out/$mode-$stack.bin")
        (cd "$out"; "./$mode/Vpc98_ide_bios_tb" "+program=$out/$mode-$stack.bin" +bus_seed=9821)
    done
done
echo 'PASS: z486 real PC-98 read/write BIOS, cached and D800h bounce buffers'
