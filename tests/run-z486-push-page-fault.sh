#!/usr/bin/env bash
# User-mode stack page faults from the Linux BusyBox startup failure.
set -euo pipefail
ulimit -c 0
cd "$(dirname "$0")/.."
out=${PUSH_PF_OUT:-$(mktemp -d)}
mkdir -p "$out"
if [[ -z ${PUSH_PF_OUT:-} ]]; then trap 'rm -rf "$out"' EXIT; fi
out=$(cd "$out"; pwd)
pipeline=${PUSH_PF_PIPELINE:-2}
cp rtl/vendor/z486/*.hex "$out/"
build() {
    local name=$1 core=$2
    mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@' |
        sed "s@^rtl/vendor/z486/z486.sv\$@$core@")
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU \
        -DZET98_Z486_PIPELINE_REGS="$pipeline" -DZET98_NATIVE_DDR -DZET98_NATIVE_DDR_FB_ONLY \
        -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj-$name" \
        --top-module z486_xms_resident_tb -GRAM_MB=64 -GPEGC_ENABLE=1 \
        -GDDR_WORDS=16384 -GTRACE_LIMIT=0 -GWATCHDOG_NS=20000000 \
        "${sources[@]}" rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
        rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv \
        rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv rtl/cpu/z486_pc98_adapter.sv \
        rtl/graphics/pc98_pegc_bus.sv rtl/graphics/pc98_pegc_control.sv \
        rtl/graphics/pc98_pegc_palette.sv rtl/graphics/pc98_pegc_memory.sv \
        rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/z486_xms_resident_tb.sv \
        > "$out/compile-$name.log" 2>&1 || { tail -n 60 "$out/compile-$name.log"; exit 1; }
}
build current rtl/vendor/z486/z486.sv
for width in 2 4; do
    for present in 0 1; do
        for push in -1 0 1 2 3 4; do
            name="push-$width-$present-$push"
            nasm -f bin -DPUSH_BYTES="$width" -DPRESENT="$present" -DFAULT_PUSH="$push" \
                tests/hardware/push_page_fault_probe.asm -o "$out/$name.bin"
            (cd "$out"; ./obj-current/Vz486_xms_resident_tb "+program=$out/$name.bin") \
                > "$out/$name.log" 2>&1 || { tail -n 20 "$out/$name.log"; exit 1; }
        done
    done
done
for present in 0 1; do
    nasm -f bin -DENTER_FRAME -DPRESENT="$present" tests/hardware/push_page_fault_probe.asm \
        -o "$out/enter-$present.bin"
    (cd "$out"; ./obj-current/Vz486_xms_resident_tb "+program=$out/enter-$present.bin") \
        > "$out/enter-$present.log" 2>&1 || { tail -n 20 "$out/enter-$present.log"; exit 1; }
done
echo "PASS: pipeline $pipeline, 26 user stack fault cases: word/DWORD PUSH, CALL, ENTER, not-present/read-only pages, saved ESP and argument/return integrity"

# Omitting rollback must fail the original four-PUSH case. Omitting the
# first-cycle bypass must fail CALL, which hands its write off on i_first.
sed '/TMPeSP <= wr_restart_esp;/d' rtl/vendor/z486/z486.sv > "$out/no-rollback.sv"
sed 's/wr_restart_esp <= i_first ? ESP : TMPeSP;/wr_restart_esp <= TMPeSP;/' \
    rtl/vendor/z486/z486.sv > "$out/no-first-cycle.sv"
sed 's/wire        mem_req_to_paging = !page_fault \&\& /wire        mem_req_to_paging = /' \
    rtl/vendor/z486/z486.sv > "$out/no-fault-gate.sv"
for name in no-rollback no-first-cycle no-fault-gate; do
    build "$name" "$out/$name.sv"
    probe=push-4-0-4
    if [[ $name == no-first-cycle ]]; then probe=push-4-0-0; fi
    if [[ $name == no-fault-gate ]]; then probe=push-4-0-1; fi
    if (cd "$out"; "./obj-$name/Vz486_xms_resident_tb" "+program=$out/$probe.bin") \
        > "$out/$name.log" 2>&1; then
        echo "FAIL: $name negative control passed"; exit 1
    fi
    grep -q 'protected-mode extended memory program failed' "$out/$name.log"
    echo "PASS: $name negative control rejected"
done
