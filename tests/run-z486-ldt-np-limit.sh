#!/usr/bin/env bash
# A segment load past the LDT limit must raise #GP(selector) without reading
# the descriptor: a not-present page past the table must not raise #PF
# (Windows 95 VMM C00013B7 client return). tests/hardware/ldt_np_limit.asm.
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
    --top-module z486_xms_resident_tb -GRAM_MB=64 -GTRACE_LIMIT=0 -GWATCHDOG_NS=20000000 "${sources[@]}" \
    rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
    rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
    rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
}
nasm -f bin tests/hardware/ldt_np_limit.asm -o "$out/t.bin"
cp rtl/vendor/z486/*.hex "$out/"
build rtl/vendor/z486/z486.sv
if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/run.log" 2>&1; then
  grep -v '^XMS EIP' "$out/run.log" | tail -n 8; echo 'FAIL: LDT limit before the descriptor read'; exit 1
fi
echo 'PASS: 300 FS loads past a not-present-backed LDT raise #GP(CFFCh), never #PF'
# Negative control: the core without the descriptor-read bound gate.
git show HEAD:rtl/vendor/z486/z486.sv 2>/dev/null > "$out/old_z486.sv" || true
if [ -s "$out/old_z486.sv" ] && ! grep -q 'dt_read_oob' "$out/old_z486.sv"; then
  build "$out/old_z486.sv"
  if (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/neg.log" 2>&1; then
    echo 'FAIL: negative control (descriptor read not gated) passed'; exit 1
  fi
  echo 'PASS: negative control without the gate fails'
fi
