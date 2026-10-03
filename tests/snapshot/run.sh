#!/usr/bin/env bash
# Replay an NP2kai snapshot on the z486 RTL (inside zet98-z486-sim, any cwd).
# Usage: tests/snapshot/run.sh SNAPDIR OUTDIR [N] [snap_gen.py options]
# IO=FILE replays "port value" I/O reads. Prints the issue-trace length and
# the tail of OUTDIR/run.log.
set -euo pipefail
cd "$(dirname "$0")/../.."
snap=$1; out=$2; n=${3:-20000}
shift $(( $# < 3 ? $# : 3 ))
mkdir -p "$out"
nasm -f bin -DPART=stage1 ${STAGE2:+-DSTAGE2=$STAGE2} tests/snapshot/snap_loader.asm -o "$out/s1.bin"
nasm -f bin -DPART=stage2 ${STAGE2:+-DSTAGE2=$STAGE2} tests/snapshot/snap_loader.asm -o "$out/s2.bin"
python3 tests/snapshot/snap_gen.py "$snap" "$out/s1.bin" "$out/s2.bin" "$out" "$@"
if [ ! -x "$out/obj/Vz486_snap_tb" ]; then
  mapfile -t sources < <(tr -d '\r' < rtl/vendor/z486/sources.txt | sed 's@^@rtl/vendor/z486/@')
  verilator --binary --timing -j 4 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
    -Wno-PINMISSING -Wno-UNOPTFLAT -DZET98_Z486 -DZ486_ALTERA_ALU -DZET98_Z486_DEBUG \
    -Irtl/vendor/z486 -Irtl/vendor/z486/x87 --Mdir "$out/obj" --top-module z486_snap_tb "${sources[@]}" \
    rtl/cpu/ao486_io_bridge.sv rtl/cpu/ao486_memory_bridge.sv rtl/cpu/ao486_memory_queue.sv rtl/cpu/ao486_bus_bridge.sv \
    rtl/cpu/pc98_ao486.sv rtl/cpu/pc98_extmem_bridge.sv rtl/cpu/pc98_lowmem_cache.sv \
    rtl/cpu/z486_pc98_adapter.sv rtl/graphics/pc98_pegc_*.sv tests/snapshot/z486_snap_tb.sv > "$out/compile.log" 2>&1 || { tail -n 40 "$out/compile.log"; exit 1; }
  cp rtl/vendor/z486/*.hex "$out/"
fi
(cd "$out"; ./obj/Vz486_snap_tb "+dir=$out" "+n=$n" ${IO:+"+io=$IO"} ${SEED:+"+seed=$SEED"} ${TBARGS:-}) > "$out/run.log" 2>&1 || true
grep -c '^I ' "$out/run.log" || true
tail -n 5 "$out/run.log"
