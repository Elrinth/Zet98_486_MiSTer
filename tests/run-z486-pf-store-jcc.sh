#!/usr/bin/env bash
# A store #PF that arrives after a younger Jcc issued must still read the
# right IDT gate (Windows 95 KERNEL32 hang). tests/hardware/pf_store_jcc.asm.
# Negative control: without clearing the Jcc kind at fault entry it hangs.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/hardware/pf_store_jcc.asm -o "$out/t.bin"
cp rtl/vendor/z486/*.hex "$out/"
build() {
  local core=$1
  mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@' |
      sed "s@^rtl/vendor/z486/z486.sv\$@$core@")
  rm -rf "$out/obj"
  verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
    -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
    --top-module z486_xms_resident_tb -GRAM_MB=64 -GTRACE_LIMIT=0 -GWATCHDOG_NS=20000000 "${sources[@]}" \
    rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
    rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
    rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
}
build rtl/vendor/z486/z486.sv
if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/run.log" 2>&1; then
  grep -v '^XMS EIP' "$out/run.log" | tail -n 10
  exit 1
fi
echo 'PASS: store #PF after an issued Jcc reaches the handler and restarts (Windows 95 KERNEL32)'
tr -d '\r' < rtl/vendor/z486/z486.sv | sed 's/end else if (any_fault_r) begin$/end else if (1'"'"'b0) begin/' > "$out/old_z486.sv"
[ "$(grep -c "end else if (1'b0) begin" "$out/old_z486.sv")" = 1 ]
build "$out/old_z486.sv"
if (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/neg.log" 2>&1; then
  echo 'FAIL: negative control passed'; exit 1
fi
echo 'PASS: negative control (Jcc kind kept through fault delivery) fails'
