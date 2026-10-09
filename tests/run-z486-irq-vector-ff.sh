#!/usr/bin/env bash
# Interrupt gates past IDTR.limit must raise #GP(vector*8+2+EXT): software
# INT DCh past a 60h-entry IDT (Windows 95's VMM reflects it from that #GP),
# an external interrupt acknowledged with vector FFh, and with a full IDT the
# vector must reach gate 255. tests/hardware/irq_vector_ff.asm.
# Negative control: without the IDT limit check the past-limit gate is used.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
build() {
  local core=$1
  mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@' |
      sed "s@^rtl/vendor/z486/z486.sv\$@$core@")
  rm -rf "$out/obj"
  verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
    -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
    --top-module z486_xms_resident_tb -GRAM_MB=64 -GPIT_PM_TEST=1 "-GIRQ_VECTOR=8'hff" \
    -GTRACE_LIMIT=0 -GWATCHDOG_NS=20000000 "${sources[@]}" \
    rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
    rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
    rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
}
run() {   # $1 = nasm define (may be empty)
  nasm -f bin ${1:+"$1"} tests/hardware/irq_vector_ff.asm -o "$out/t.bin"
  (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/run.log" 2>&1
}
cp rtl/vendor/z486/*.hex "$out/"
build rtl/vendor/z486/z486.sv
for def in -DSOFT_INT "" -DFULL_IDT; do
  if ! run "$def"; then
    grep -v '^XMS EIP' "$out/run.log" | tail -n 8; echo "FAIL: ${def:-short IDT, external vector FFh}"; exit 1
  fi
done
echo 'PASS: gates past IDTR.limit raise #GP (INT DCh 6E2h, external vector FFh 7FBh); full IDT reaches gate 255'
tr -d '\r' < rtl/vendor/z486/z486.sv |
  sed 's/\.selector_oob(prot_int_gate_test ? idt_oob_r : selector_oob_wire),/.selector_oob(selector_oob_wire),/' > "$out/old_z486.sv"
[ "$(grep -c 'selector_oob(selector_oob_wire),' "$out/old_z486.sv")" = 1 ]
build "$out/old_z486.sv"
if run -DSOFT_INT; then echo 'FAIL: negative control (no IDT limit check) passed'; exit 1; fi
echo 'PASS: negative control without the IDT limit check fails'
