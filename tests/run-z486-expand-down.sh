#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/expand_down_stack_probe.asm -o "$out/cs.bin"
cp rtl/vendor/z486/*.hex "$out/"
# build_and_run SEGMENTATION_UNIT: z486 with that segmentation unit runs the probe.
build_and_run() {
    local sources
    mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
    for i in "${!sources[@]}"; do
        if [[ "${sources[$i]}" == */segmentation_unit.sv ]]; then sources[$i]=$1; fi
    done
    rm -rf "$out/obj"
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
        -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
        --top-module z486_xms_resident_tb -GRAM_MB=64 "${sources[@]}" \
        rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
        rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
        rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 80 "$out/compile.log"; return 1; }
    (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/cs.bin")
}
build_and_run rtl/vendor/z486/segmentation_unit.sv
echo 'PASS: expand-down 32-bit and 16-bit stacks: push/pop, call, interrupt gate'
# Negative control: limit checks that ignore expand-down must fail the probe
# (the old core took #SS on the first push and ended in a triple fault).
tr -d '\r' < rtl/vendor/z486/segmentation_unit.sv \
    | sed 's/(seg_ed_r ? ed_fault : limit_violated)/limit_violated/' > "$out/old_seg.sv"
! cmp -s <(tr -d '\r' < rtl/vendor/z486/segmentation_unit.sv) "$out/old_seg.sv"
if build_and_run "$out/old_seg.sv" > "$out/neg.log" 2>&1; then
    echo 'FAIL: expand-down ignored but the probe passed'; exit 1
fi
grep -q -i 'failed\|watchdog\|fatal' "$out/neg.log" || { tail -20 "$out/neg.log"; exit 1; }
echo 'PASS: limit check without expand-down rejected'
