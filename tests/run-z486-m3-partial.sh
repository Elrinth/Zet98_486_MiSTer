#!/usr/bin/env bash
# Byte/word load right after a register-memory ALU op on the same register
# (tests/hardware/m3_partial_probe.asm). The hazard needs back-to-back direct
# loads, which the released registered-EA pipeline (2) rarely produces; the
# unregistered pipeline (0) hits it. PIPELINES selects the builds checked.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/m3_partial_probe.asm -o "$out/t.bin"
cp rtl/vendor/z486/*.hex "$out/"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
for pipeline in ${PIPELINES:-0 2}; do
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
        -DZET98_Z486_PIPELINE_REGS=$pipeline \
        -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj$pipeline" \
        --top-module z486_xms_resident_tb -GRAM_MB=64 "${sources[@]}" \
        rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
        rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
        rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 ||
        { tail -n 60 "$out/compile.log"; exit 1; }
    (cd "$out"; "$out/obj$pipeline/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/run.log" 2>&1 ||
        { grep -v '^XMS EIP' "$out/run.log" | tail -n 8; echo "FAIL: M3 then partial load, pipeline $pipeline"; exit 1; }
    echo "PASS: partial loads merge with an older register-memory ALU result (pipeline $pipeline)"
done
