#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/cache_insn_probe.asm -o "$out/cs.bin"
cp rtl/vendor/z486/*.hex "$out/"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
    -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
    --top-module z486_xms_resident_tb -GRAM_MB=64 "${sources[@]}" \
    rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
    rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
    rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 80 "$out/compile.log"; exit 1; }
(cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/cs.bin")
echo 'PASS: INVD and WBINVD execute as no-ops, BSWAP works, CPUID faults (#UD)'
# Negative control: without the INVD/WBINVD decode they take #UD (HSB.EXE hang).
tr -d '' < rtl/vendor/z486/decoder.sv | sed 's/cache_nop = prefix_0f \&\& (opcode\[7:1\] == 7.b0000100);/cache_nop = 1'"'"'b0;/' > "$out/old_decoder.sv"
! cmp -s <(tr -d '' < rtl/vendor/z486/decoder.sv) "$out/old_decoder.sv"
mapfile -t sources < <(tr -d '' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@' | sed "s@rtl/vendor/z486/decoder.sv@$out/old_decoder.sv@")
rm -rf "$out/obj"
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD     -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG     -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj"     --top-module z486_xms_resident_tb -GRAM_MB=64 "${sources[@]}"     rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv     rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv     rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile_old.log" 2>&1 || { tail -n 40 "$out/compile_old.log"; exit 1; }
if (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/cs.bin") > "$out/neg.log" 2>&1; then
    echo 'FAIL: INVD/WBINVD #UD accepted'; exit 1
fi
echo 'PASS: decoder without INVD/WBINVD rejected'
