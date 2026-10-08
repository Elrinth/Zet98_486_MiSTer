#!/usr/bin/env bash
set -euo pipefail
# Test production direct-load admission with self-authored boundary programs.
# Bound the entire local simulation including compilation.
if [ "${LOAD_LIMIT_TEST_INNER:-0}" != 1 ]; then
 exec timeout --kill-after=10s 900s env LOAD_LIMIT_TEST_INNER=1 bash "$0"
fi
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
evidence="$out/evidence"
mkdir "$evidence"
mkdir "$evidence/cases"
for generator in cpu edges real overlap store_replay replay_fault replay_alignment; do
    python3 "tests/make_vipt_segment_${generator}.py" "$evidence/$generator"
    for asm in "$evidence/$generator"/*.asm; do
        cp "$asm" "$evidence/cases/$generator-$(basename "$asm")"
    done
done
cp rtl/vendor/z486/*.hex "$out/"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
 -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
 -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
 --top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 -GPM_PAYLOAD_TEST=1 -GPM_MIN_DDR=0 \
 -GTRACE_LIMIT=0 "${sources[@]}" \
 rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
 rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
 rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$evidence/compile.log" 2>&1 || { tail -n 40 "$evidence/compile.log"; exit 1; }
for asm in "$evidence"/cases/*.asm; do
 name=$(basename "$asm" .asm)
 nasm -f bin "$asm" -o "$out/$name.bin"
 if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/$name.bin") > "$evidence/$name.log" 2>&1; then
  tail -n 15 "$evidence/$name.log"; echo "FAIL $name"; exit 1
 fi
 echo "PASS $name"
done
echo 'PASS: production segment admission tests'
