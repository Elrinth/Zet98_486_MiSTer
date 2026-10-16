#!/usr/bin/env bash
# DrawDibBegin with a store #PF on the write-protected header page, then the
# BITMAPINFO copies and pointer reloads (Magical Chase). tests/hardware/rep_movs_wp.asm.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/rep_movs_wp.asm -o "$out/t.bin"
cp rtl/vendor/z486/*.hex "$out/"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
fail=0
for wait in ${RANDOM_WAITS:-0 6}; do
  rm -rf "$out/obj"
  verilator --binary --timing -j 4 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
    -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
    --top-module z486_xms_resident_tb -GRAM_MB=64 -GTRACE_LIMIT=0 -GWATCHDOG_NS=200000000 -GPIT_PM_TEST=1 -GRANDOM_WAIT=$wait "${sources[@]}" \
    rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
    rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
    rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
  for period in ${IRQ_PERIODS:-97 131 173 229 311 457 613 1009 1999}; do
    if (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin" "+irq_period=$period") > "$out/run.log" 2>&1; then
      echo "PASS: RANDOM_WAIT=$wait irq_period=$period $(grep -o 'accepted=[0-9]*' "$out/run.log" | tail -n 1)"
    else
      echo "FAIL: RANDOM_WAIT=$wait irq_period=$period"
      grep -E 'CPU REPORT|fatal|Error' "$out/run.log" | head -n 4
      fail=1
    fi
  done
done
exit $fail
