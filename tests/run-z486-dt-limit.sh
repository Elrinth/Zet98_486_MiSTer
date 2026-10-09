#!/usr/bin/env bash
# Segment loads past the GDT/LDT limit must raise #GP(selector & FFFCh)
# (Windows 95 VMM client-segment reload). tests/hardware/dt_limit.asm.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
build() {
  local core=$1
  mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@' |
      sed "s@^rtl/vendor/z486/protection.sv\$@$core@")
  rm -rf "$out/obj"
  verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
    -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
    --top-module z486_xms_resident_tb -GRAM_MB=64 -GTRACE_LIMIT=0 -GWATCHDOG_NS=20000000 "${sources[@]}" \
    rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
    rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
    rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
}
nasm -f bin tests/hardware/dt_limit.asm -o "$out/t.bin"
cp rtl/vendor/z486/*.hex "$out/"
build rtl/vendor/z486/protection.sv
if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/run.log" 2>&1; then
  grep -v '^XMS EIP' "$out/run.log" | tail -n 8; echo 'FAIL: descriptor-table limit'; exit 1
fi
echo 'PASS: DS/ES/FS/GS/SS, LFS/LES and POP DS past the GDT/LDT limit raise #GP(selector & FFFCh)'
# Negative control: the protection unit without the descriptor-table limit terms.
git show HEAD:rtl/vendor/z486/protection.sv 2>/dev/null | tr -d '' > "$out/old_protection.sv" || true
if ! grep -q 'Selector past the GDT/LDT limit' "$out/old_protection.sv" && [ -s "$out/old_protection.sv" ]; then
  build "$out/old_protection.sv"
  if (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/neg.log" 2>&1; then
    echo 'FAIL: negative control (no descriptor-table limit check) passed'; exit 1
  fi
  echo 'PASS: negative control without the limit check fails'
fi
