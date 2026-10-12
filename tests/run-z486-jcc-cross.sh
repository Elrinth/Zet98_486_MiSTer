#!/usr/bin/env bash
# A branch whose displacement is on the next page must fault or run, not stall (Win95 KERNEL32 je at BFF94FFF).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
cp rtl/vendor/z486/*.hex "$out/"
build() {
  local core=$1
  mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@' |
      sed "s@^rtl/vendor/z486/z486.sv\$@$core@")
  rm -rf "$out/obj"
  verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
    -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" \
    --top-module z486_xms_resident_tb -GRAM_MB=64 -GTRACE_LIMIT=0 -GWATCHDOG_NS=20000000 -GRANDOM_WAIT=$2 "${sources[@]}" \
    rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
    rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
    rtl/cpu/z486_pc98_adapter.sv tests/z486_xms_resident_tb.sv > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
}
for wait in 0 20; do
  build rtl/vendor/z486/z486.sv $wait
  for where in "" -DHIGH; do
    nasm -f bin $where tests/hardware/jcc_cross.asm -o "$out/t.bin"
    if ! (cd "$out"; "$out/obj/Vz486_xms_resident_tb" "+program=$out/t.bin") > "$out/run.log" 2>&1; then
      grep -v '^XMS EIP' "$out/run.log" | tail -n 10; echo "FAIL: RANDOM_WAIT=$wait ${where:-low memory}"
      exit 1
    fi
  done
done
echo 'PASS: Jcc/JMP/LOOP/JECXZ rel8, Jcc rel32 and split ModRM/immediate/0F instructions with their tail on the next page (cached, out of TLB, not present; CALL, RET and ring-3 entry; fast and random bus waits; low and extended memory) (Windows 95 KERNEL32 BFF94FFF, Explorer 00407FFF)'
