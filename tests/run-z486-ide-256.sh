#!/usr/bin/env bash
# Actual z486 CPU running the INT 1Bh service with 256-byte caller sectors
# (native SASI-era HDI images) over 512-byte ATA blocks: reads starting on
# even/odd sectors, CHS, sense, and half-block writes that must preserve the
# other half. Expected block counts are computed independently here.
set -euo pipefail
if [[ ${1:-} != bounded ]]; then
    exec timeout --signal=TERM --kill-after=10s 900s bash "$0" bounded
fi
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
read_blocks=$(python3 - <<'PY'
sectors=[0,1,2,3,35,100,101]
lengths=[1,2,255,256,257,300,511,512,513,767,768,1000,1024,1025]
blocks=lambda s,n:((s*256+n-1)>>9)-((s*256)>>9)+1
print(sum(blocks(s,n) for s in sectors for n in lengths)+blocks(35,300))
PY
)
mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
cp rtl/vendor/z486/*.hex "$out/"
build() { # name expect_reads expect_writes write_test
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
        -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/$1" \
        --top-module pc98_ide_bios_tb -GEXPECT_READS=$2 -GEXPECT_WRITES=$3 -GWRITE_TEST=$4 \
        -GWATCHDOG_NS=1000000000 "${sources[@]}" \
        rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv \
        rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv rtl/cpu/pc98_ao486.sv \
        rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
        rtl/cpu/z486_pc98_adapter.sv tests/pc98_ide_bios_tb.sv \
        > "$out/$1.log" 2>&1 || { tail -n 60 "$out/$1.log"; exit 1; }
}
build read "$read_blocks" 0 0
build write "$((read_blocks+6))" 3 1
nasm -f bin tests/pc98_ide_256_sweep.asm -o "$out/read.bin"
nasm -DBIOS_WRITE_SWEEP=1 -f bin tests/pc98_ide_256_sweep.asm -o "$out/write.bin"
echo "256-byte sectors, reads only: $read_blocks block reads expected"
(cd "$out"; ./read/Vpc98_ide_bios_tb "+program=$out/read.bin" | grep -E 'PASS|Fatal|fail')
(cd "$out"; ./read/Vpc98_ide_bios_tb "+program=$out/read.bin" +bus_seed=9821 | grep -E 'PASS|Fatal|fail')
echo "256-byte sectors with half-block writes"
(cd "$out"; ./write/Vpc98_ide_bios_tb "+program=$out/write.bin" | grep -E 'PASS|Fatal|fail')
# Negative: ignore the in-block offset on reads; odd sectors must then fail.
mkdir -p "$out/neg/software"
tr -d '\r' < software/pc98_ide_read_bios.inc | sed 's/^    add si,\[bp-516\]$/    nop/' > "$out/neg/software/pc98_ide_read_bios.inc"
grep -q '^    nop$' "$out/neg/software/pc98_ide_read_bios.inc" || { echo 'negative patch not applied'; exit 1; }
cp tests/pc98_ide_256_sweep.asm "$out/neg/"
(cd "$out/neg"; nasm -f bin pc98_ide_256_sweep.asm -o "$out/neg.bin")
if (cd "$out"; ./read/Vpc98_ide_bios_tb "+program=$out/neg.bin") > "$out/neg.log" 2>&1; then
    echo 'ERROR: ignoring the block offset was accepted'; exit 1
fi
grep -q 'reported failure' "$out/neg.log"
echo 'PASS: 256-byte sectors, even/odd starts, CHS, sense and half-block writes; ignored offset rejected'
