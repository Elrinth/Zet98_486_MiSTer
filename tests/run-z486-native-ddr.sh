#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=${NATIVE_DDR_OUT:-$(mktemp -d)}
mkdir -p "$out"
if [[ -z ${NATIVE_DDR_OUT:-} ]]; then trap 'rm -rf "$out"' EXIT; fi
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
for name in native_ddr native_exec pegc_cpu stack_allocation; do
    nasm -f bin "tests/hardware/${name}_probe.asm" -o "$out/$name.bin"
done
nasm -f bin -Isoftware/ tests/hardware/native_init_probe.asm -o "$out/native_init.bin"
cp rtl/vendor/z486/*.hex "$out/"
for native in 0 1 2; do
    flags=()
    if [[ $native != 0 ]]; then flags+=(-DZET98_NATIVE_DDR); fi
    if [[ $native == 2 ]]; then flags+=(-DZET98_NATIVE_DDR_FB_ONLY); fi
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU \
        -DZET98_Z486_PIPELINE_REGS=2 "${flags[@]}" \
        -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj-$native" \
        --top-module z486_xms_resident_tb -GRAM_MB=64 -GPEGC_ENABLE=1 \
        -GDDR_WORDS=16384 -GTRACE_LIMIT=0 -GWATCHDOG_NS=400000000 \
        "${sources[@]}" rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
        rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv \
        rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv rtl/cpu/z486_pc98_adapter.sv \
        rtl/graphics/pc98_pegc_bus.sv rtl/graphics/pc98_pegc_control.sv \
        rtl/graphics/pc98_pegc_palette.sv rtl/graphics/pc98_pegc_memory.sv \
        rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/z486_xms_resident_tb.sv \
        > "$out/compile-$native.log" 2>&1 || { tail -n 70 "$out/compile-$native.log";exit 1; }
    for name in native_ddr native_exec pegc_cpu stack_allocation; do
        (cd "$out"; "./obj-$native/Vz486_xms_resident_tb" "+program=$out/$name.bin") \
            > "$out/$name-$native.log" 2>&1 || { tail -n 20 "$out/$name-$native.log";exit 1; }
        echo "NATIVE_DDR=$native $name"
        grep -E 'CPU REPORT|RATE |PASS:' "$out/$name-$native.log"
    done
    for segment in 0000 6000 da00; do
        (cd "$out"; "./obj-$native/Vz486_xms_resident_tb" "+program=$out/native_init.bin" "+program_cs=$segment") \
            > "$out/native_init-$native-$segment.log" 2>&1 || { tail -n 20 "$out/native_init-$native-$segment.log";exit 1; }
        echo "NATIVE_DDR=$native memory init CS=$segment"
        grep -E 'RATE |PASS:' "$out/native_init-$native-$segment.log"
    done
    if [[ $native != 0 ]]; then
        (cd "$out"; "./obj-$native/Vz486_xms_resident_tb" "+program=$out/pegc_cpu.bin" +reset_after_read=1) \
            > "$out/reset-$native.log" 2>&1 || { tail -n 20 "$out/reset-$native.log";exit 1; }
        grep -E 'RESET|RATE |PASS:' "$out/reset-$native.log"
    fi
done
