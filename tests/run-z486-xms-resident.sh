#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p xms-sim-output
out=$PWD/xms-sim-output
nasm -f bin tests/hardware/xms_resident_probe.asm -o "$out/resize.bin"
nasm -f bin -DCOPY_CONTROL=1 tests/hardware/xms_resident_probe.asm -o "$out/copy.bin"
nasm -f bin tests/hardware/unreal_cs_probe.asm -o "$out/cs.bin"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
-Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
-Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
--top-module z486_xms_resident_tb -GRAM_MB=64 "${sources[@]}" \
rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 80 "$out/compile.log"; exit 1; }
cp rtl/vendor/z486/*.hex .
set +e
"$out/obj/Vz486_xms_resident_tb" "+program=$out/cs.bin" > "$out/cs.log" 2>&1
s=$?
"$out/obj/Vz486_xms_resident_tb" "+program=$out/copy.bin" +resized=0 +resident=test-assets/himemx-resident.bin > "$out/copy.log" 2>&1
c=$?
"$out/obj/Vz486_xms_resident_tb" "+program=$out/resize.bin" +resized=1 +resident=test-assets/himemx-resident.bin > "$out/resize.log" 2>&1
r=$?
tail -n 8 "$out/cs.log"
tail -n 14 "$out/copy.log"
tail -n 30 "$out/resize.log"
echo "cs_exit=$s copy_exit=$c resize_exit=$r"
exit $((s || c || r))
