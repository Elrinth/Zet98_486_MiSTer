#!/usr/bin/env bash
# A store #PF that arrives after a younger load reached writeback restarts at
# the store, so the load's register write must be cancelled (Windows 95 boot).
# tests/hardware/pf_store_load.asm, release and default pipeline profiles.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/pf_store_load.asm -o "$out/t.bin"
cp rtl/vendor/z486/*.hex "$out/"
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
for regs in ${PIPELINE_PROFILES:-7 2}; do
  for wait in ${RANDOM_WAITS:-0 6}; do
    rm -rf "$out/obj"
    verilator --binary --timing -j 4 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
      -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZET98_Z486_PIPELINE_REGS=$regs \
      -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
      --top-module z486_xms_resident_tb -GRAM_MB=64 -GTRACE_LIMIT=0 -GWATCHDOG_NS=20000000 \
      -GRANDOM_WAIT=$wait "${sources[@]}" \
      rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
      rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
      rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
    if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/run.log" 2>&1; then
      grep -v '^XMS EIP' "$out/run.log" | tail -n 6
      echo "FAIL: PIPELINE_REGS=$regs RANDOM_WAIT=$wait"; exit 1
    fi
    echo "PASS: PIPELINE_REGS=$regs RANDOM_WAIT=$wait store #PF cancels the younger load writeback"
  done
done
