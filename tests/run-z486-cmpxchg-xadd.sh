#!/usr/bin/env bash
# 486 CMPXCHG and XADD on the z486 (tests/hardware/cmpxchg_xadd_probe.asm,
# generated and Unicorn-checked by tests/make_cmpxchg_xadd_probe.py).
# tests/hardware/cmpxchg_xadd_fault_probe.asm: faulting writes (#GP, #PF)
# leave registers, memory and flags intact and the instruction restarts.
# Negative control: the decoder without the two opcodes must fail (#UD).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/cmpxchg_xadd_probe.asm -o "$out/cx.bin"
nasm -f bin tests/hardware/cmpxchg_xadd_fault_probe.asm -o "$out/cxf.bin"
cp rtl/vendor/z486/*.hex "$out/"
build() {
    local decoder=$1
    mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@' |
        sed "s@^rtl/vendor/z486/decoder.sv\$@$decoder@")
    rm -rf "$out/obj"
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
        -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
        --top-module z486_xms_resident_tb -GRAM_MB=64 "${sources[@]}" \
        rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
        rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
        rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 ||
        { tail -n 80 "$out/compile.log"; exit 1; }
}
build rtl/vendor/z486/decoder.sv
(cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/cx.bin")
echo 'PASS: CMPXCHG and XADD (8/16/32-bit, register and memory, LOCK) match the model'
(cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/cxf.bin")
echo 'PASS: faulting CMPXCHG/XADD writes (#GP, #PF) and reads restart with state intact'
tr -d '\r' < rtl/vendor/z486/decoder.sv |
    sed -e 's/instr_xadd = prefix_0f && (opcode\[7:1\] == 7.b1100000);/instr_xadd = 1'"'"'b0;/' \
        -e 's/instr_cmpxchg = prefix_0f && (opcode\[7:1\] == 7.b1011000);/instr_cmpxchg = 1'"'"'b0;/' \
    > "$out/old_decoder.sv"
[ "$(grep -c "instr_xadd = 1'b0;\|instr_cmpxchg = 1'b0;" "$out/old_decoder.sv")" = 2 ]
build "$out/old_decoder.sv"
if (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/cx.bin") > "$out/neg.log" 2>&1; then
    echo 'FAIL: decoder without CMPXCHG/XADD accepted'; exit 1
fi
grep -q 'EBP=0000ffff' "$out/neg.log" || { tail -n 5 "$out/neg.log"; echo 'FAIL: negative control did not take #UD'; exit 1; }
echo 'PASS: decoder without CMPXCHG/XADD rejected (#UD)'
