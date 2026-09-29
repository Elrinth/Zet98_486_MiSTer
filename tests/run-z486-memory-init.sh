#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
for ram in 0 16 64; do
    nasm -Isoftware/ -DTOP_MB="$ram" -DSIM=1 -f bin software/z98mem.asm -o "$out/init.bin"
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
        -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj-$ram" \
        --top-module ao486_extmem_tb -GRAM_MB="$ram" -GDOS_PROBE=1 -GMEMORY_INIT=1 -GLOWMEM_CACHE=1 \
        "${sources[@]}" rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
        rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv \
        rtl/cpu/pc98_lowmem_cache.sv rtl/cpu/z486_pc98_adapter.sv tests/ao486_extmem_tb.sv \
        > "$out/compile-$ram.log" 2>&1 || { tail -n 60 "$out/compile-$ram.log"; exit 1; }
    cp rtl/vendor/z486/*.hex "$out/"
    for flag in 231 167; do
        (cd "$out"; "./obj-$ram/Vao486_extmem_tb" "+program=$out/init.bin" "+identity_flag=$flag")
    done
    if [ "$ram" = 64 ]; then
        cp software/z98mem.asm "$out/old.asm"
        sed '/and byte \[es:501h\], 0bfh/d' software/z98mem_probe.inc > "$out/z98mem_probe.inc"
        nasm -I"$out/" -DTOP_MB=64 -DSIM=1 -f bin "$out/old.asm" -o "$out/old.bin"
        if (cd "$out"; "./obj-$ram/Vao486_extmem_tb" "+program=$out/old.bin" > "$out/negative.log" 2>&1); then
            echo 'FAIL: old V30 identification accepted'; exit 1
        fi
        grep -q 'incorrect CPU identity correction' "$out/negative.log"
        echo 'PASS: old V30 metadata negative rejected'
    fi
done
