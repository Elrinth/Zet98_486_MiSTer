#!/usr/bin/env bash
# IMUL after a shift whose count reached the operand width (tests/hardware/imul_shift_overflow.asm):
# every IMUL form behind SHR/SHL/SAR overflow, Creamy Mami's exact order, random bus waits,
# the plain test profile and the shipped one (native DDR, 32 KB icache, write hold 2).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/imul_shift_overflow.asm -o "$out/t.bin"
cp rtl/vendor/z486/*.hex "$out/"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
for profile in ${PROFILES:-plain release}; do
    flags=(-DZET98_Z486_PIPELINE_REGS=2)
    if [[ $profile == release ]]; then
        flags+=(-DZET98_NATIVE_DDR -DZET98_Z486_ICACHE_SET_BITS=9 -DZET98_NATIVE_WRITE_HOLD=2 -DZET98_UPPER_RAM_ICACHE)
    fi
    for wait in ${WAITS:-0 3 7}; do
        verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
            -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG "${flags[@]}" \
            -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj-$profile-$wait" \
            --top-module z486_xms_resident_tb -GRAM_MB=64 -GDDR_WORDS=16384 -GRANDOM_WAIT=$wait \
            -GWATCHDOG_NS=900000000 "${sources[@]}" \
            rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
            rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
            rtl/cpu/z486_pc98_adapter.sv rtl/graphics/pc98_pegc_bus.sv rtl/graphics/pc98_pegc_control.sv \
            rtl/graphics/pc98_pegc_palette.sv rtl/graphics/pc98_pegc_memory.sv \
            rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 ||
            { tail -n 60 "$out/compile.log"; exit 1; }
        (cd "$out"; "$out/obj-$profile-$wait/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/run.log" 2>&1 ||
            { grep -v '^XMS EIP' "$out/run.log" | tail -n 8; echo "FAIL: IMUL after an overflowing shift, $profile profile, random wait $wait"; exit 1; }
        echo "PASS: IMUL after an overflowing shift ($profile profile, random wait $wait)"
    done
done
