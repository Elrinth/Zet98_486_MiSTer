#!/usr/bin/env bash
set -euo pipefail
# Bound the entire local simulation including compilation.
if [ "${SEGMENT_TEST_INNER:-0}" != 1 ]; then
 exec timeout --kill-after=10s 600s env SEGMENT_TEST_INNER=1 bash "$0"
fi
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
evidence=${SEGMENT_EVIDENCE:-/project/segment-admission-evidence}
mkdir "$evidence"
python3 "${SEGMENT_CASE_GENERATOR:-tests/make_vipt_segment_cpu.py}" "$evidence/cases"
python3 "${SEGMENT_CANDIDATE_GENERATOR:-tests/make_vipt_segment_candidate.py}" "$evidence/z486-admission.sv"
cp rtl/vendor/z486/*.hex "$out/"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
for i in "${!sources[@]}"; do
 if [ "${sources[$i]}" = rtl/vendor/z486/z486.sv ]; then sources[$i]="$evidence/z486-admission.sv"; fi
done
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
 -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
 -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
 --top-module z486_xms_resident_tb -GRAM_MB=64 -GDOS_PROBE=1 -GPM_PAYLOAD_TEST=1 -GPM_MIN_DDR=0 \
 -GTRACE_LIMIT=0 "${sources[@]}" \
 rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_bus_bridge.sv \
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
echo 'PASS: simulation-only admission boundary experiment; no production CPU change'
