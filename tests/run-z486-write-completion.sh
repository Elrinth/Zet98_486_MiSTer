#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
cd "$(dirname "$0")/.."
out=${WRITE_COMPLETE_OUT:-$(mktemp -d)}
mkdir -p "$out"
if [[ -z ${WRITE_COMPLETE_OUT:-} ]]; then trap 'rm -rf "$out"' EXIT; fi
out=$(cd "$out"; pwd)
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
cp rtl/vendor/z486/*.hex "$out/"
for name in native_ddr native_exec pegc_cpu stack_allocation pf_store_jcc cmpxchg_xadd_fault; do
    source="tests/hardware/${name}_probe.asm"
    if [[ $name == pf_store_jcc ]]; then source=tests/hardware/pf_store_jcc.asm; fi
    nasm -f bin "$source" -o "$out/$name.bin"
done
nasm -f bin -Isoftware/ tests/hardware/native_init_probe.asm -o "$out/native_init.bin"
for early in 0 1; do
    verilator --binary --timing -j 4 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU \
        -DZET98_Z486_PIPELINE_REGS=2 -DZET98_NATIVE_DDR -DZET98_NATIVE_DDR_FB_ONLY \
        -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj-$early" \
        --top-module z486_xms_resident_tb -GRAM_MB=64 -GPEGC_ENABLE=1 \
        -GEARLY_WRITE_COMPLETE="$early" -GDDR_WORDS=16384 -GTRACE_LIMIT=0 \
        -GWATCHDOG_NS=400000000 "${sources[@]}" \
        rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
        rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv \
        rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv rtl/cpu/z486_pc98_adapter.sv \
        rtl/graphics/pc98_pegc_bus.sv rtl/graphics/pc98_pegc_control.sv \
        rtl/graphics/pc98_pegc_palette.sv rtl/graphics/pc98_pegc_memory.sv \
        rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/z486_xms_resident_tb.sv \
        > "$out/compile-$early.log" 2>&1 || { tail -n 60 "$out/compile-$early.log"; exit 1; }
    for name in native_ddr native_exec pegc_cpu stack_allocation pf_store_jcc cmpxchg_xadd_fault; do
        (cd "$out"; "./obj-$early/Vz486_xms_resident_tb" "+program=$out/$name.bin") \
            > "$out/$name-$early.log" 2>&1 || { tail -n 25 "$out/$name-$early.log"; exit 1; }
        echo "EARLY_WRITE_COMPLETE=$early $name"
        grep -E 'CPU REPORT|RATE |PASS:' "$out/$name-$early.log"
    done
    for segment in 0000 6000 da00; do
        (cd "$out"; "./obj-$early/Vz486_xms_resident_tb" "+program=$out/native_init.bin" "+program_cs=$segment") \
            > "$out/native_init-$early-$segment.log" 2>&1 || { tail -n 25 "$out/native_init-$early-$segment.log"; exit 1; }
    done
    (cd "$out"; "./obj-$early/Vz486_xms_resident_tb" "+program=$out/pegc_cpu.bin" +reset_after_read=1) \
        > "$out/reset-$early.log" 2>&1 || { tail -n 25 "$out/reset-$early.log"; exit 1; }
    for speed in 1 2 3; do
        (cd "$out"; "./obj-$early/Vz486_xms_resident_tb" "+program=$out/pegc_cpu.bin" "+cpu_speed=$speed") \
            > "$out/speed-$early-$speed.log" 2>&1 || { tail -n 25 "$out/speed-$early-$speed.log"; exit 1; }
    done
    for width in 2 4; do
        for present in 0 1; do
            for push in -1 0 1 2 3 4; do
                name="push-$width-$present-$push"
                nasm -f bin -DPUSH_BYTES="$width" -DPRESENT="$present" -DFAULT_PUSH="$push" \
                    tests/hardware/push_page_fault_probe.asm -o "$out/$name.bin"
                (cd "$out"; "./obj-$early/Vz486_xms_resident_tb" "+program=$out/$name.bin") \
                    > "$out/$name-$early.log" 2>&1 || { tail -n 25 "$out/$name-$early.log"; exit 1; }
            done
        done
    done
    for present in 0 1; do
        nasm -f bin -DENTER_FRAME -DPRESENT="$present" tests/hardware/push_page_fault_probe.asm \
            -o "$out/enter-$present.bin"
        (cd "$out"; "./obj-$early/Vz486_xms_resident_tb" "+program=$out/enter-$present.bin") \
            > "$out/enter-$present-$early.log" 2>&1 || { tail -n 25 "$out/enter-$present-$early.log"; exit 1; }
    done
    echo "PASS: completion=$early, 26 stack-fault cases and all CPU speed settings"
done
