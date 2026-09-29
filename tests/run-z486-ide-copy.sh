#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} != bounded ]]; then
    exec timeout --signal=TERM --kill-after=10s 600s bash "$0" bounded
fi
cd "$(dirname "$0")/.."
root=$PWD
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
cp rtl/vendor/z486/*.hex "$out/"
verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
    -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/cpu" \
    --top-module pc98_ide_bios_tb -GEXPECT_READS=288 -GWATCHDOG_NS=1000000000 "${sources[@]}" \
    rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
    rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv \
    rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
    rtl/cpu/z486_pc98_adapter.sv tests/pc98_ide_bios_tb.sv \
    > "$out/compile.log" 2>&1 || { tail -n 60 "$out/compile.log"; exit 1; }
mkdir -p "$out/software"
cp software/pc98_ide_read_bios.inc "$out/software/pc98_ide_read_bios.inc"
for stack in cached uncached; do
    flags=()
    if [[ "$stack" == uncached ]]; then flags=(-DBIOS_HIGH_STACK=1); fi
    nasm "${flags[@]}" -f bin tests/pc98_ide_copy_sweep.asm -o "$out/$stack.bin"
    echo "Wide-copy actual CPU: 208 cases, $stack stack"
    (cd "$out"; ./cpu/Vpc98_ide_bios_tb "+program=$out/$stack.bin")
    (cd "$out"; ./cpu/Vpc98_ide_bios_tb "+program=$out/$stack.bin" +bus_seed=9821)
done
python3 - "$out/software/pc98_ide_read_bios.inc" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text();assert s.count('    and cx,3\n')==1
p.write_text(s.replace('    and cx,3\n','    xor cx,cx\n'))
PY
(cd "$out"; nasm -f bin "$root/tests/pc98_ide_copy_sweep.asm" -o negative.bin)
if (cd "$out"; ./cpu/Vpc98_ide_bios_tb "+program=$out/negative.bin") > "$out/negative.log" 2>&1; then
    echo 'ERROR: missing-tail negative passed'; exit 1
fi
grep -F 'BIOS test reported failure' "$out/negative.log" | tail -n 3
echo 'PASS: actual CPU wide-copy 16 alignments x13 lengths, cached/uncached stacks, normal/random bus; omitted-tail negative rejected'
