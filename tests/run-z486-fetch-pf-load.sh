#!/usr/bin/env bash
# An instruction-fetch #PF must keep an older load's register write
# (Windows 95 MSVFW32 DrawDibBegin, Magical Chase). tests/hardware/fetch_pf_load.asm.
# RANDOM_WAIT=N (default 0 and 6) runs with random bus waits.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/fetch_pf_load.asm -o "$out/t.bin"
cp rtl/vendor/z486/*.hex "$out/"
build() {
  local core=$1 wait=$2
  mapfile -t sources < <(tr -d '' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@' |
      sed "s@^rtl/vendor/z486/z486.sv\$@$core@")
  rm -rf "$out/obj"
  verilator --binary --timing -j 4 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD     -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG     -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj"     --top-module z486_xms_resident_tb -GRAM_MB=64 -GTRACE_LIMIT=0 -GWATCHDOG_NS=50000000 -GRANDOM_WAIT=$wait "${sources[@]}"     rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv     rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv     rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
}
for wait in ${RANDOM_WAITS:-0 6}; do
  build rtl/vendor/z486/z486.sv $wait
  if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/run.log" 2>&1; then
    grep -v '^XMS EIP' "$out/run.log" | tail -n 12
    echo "FAIL: RANDOM_WAIT=$wait"; exit 1
  fi
  echo "PASS: RANDOM_WAIT=$wait load before a code-fetch #PF (MSVFW32 DrawDibBegin)"
done
tr -d '' < rtl/vendor/z486/z486.sv | sed 's/!mem_servicing \&\& !vipt_load_busy \&\& !i_issue \&\&/!mem_servicing \&\&/' > "$out/old_z486.sv"
[ "$(grep -c '!mem_servicing && !vipt_load_busy && !i_issue' "$out/old_z486.sv")" = 0 ]
build "$out/old_z486.sv" 0
if (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/neg.log" 2>&1; then
  echo 'FAIL: negative control passed'; exit 1
fi
echo 'PASS: negative control (fetch fault ignores pending loads) fails'
