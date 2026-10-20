#!/usr/bin/env bash
# Main-RAM line buffer in front of the real SDRAMC (posted writes, CPURD4
# fills, font video traffic) with an ao486_memory_bridge-timed CPU: random
# byte/word writes, reads, RMW and dword pairs checked against program order.
# Negative control: without write snooping a stale read must be caught.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -frelaxed -fsynopsys --workdir="$out" tests/lcell_model.vhd Zet98/sdramc.vhd \
    Zet98/mainram_linebuf.vhd tests/sdram_linebuf_tb.vhd
ghdl -e --std=08 -frelaxed -fsynopsys --workdir="$out" sdram_linebuf_tb
for cfg in "90 0 2 1" "90 2500 2 7" "90 7300 2 42" "90 4100 3 9" "90 900 2 13" "50 3300 2 17"; do
    set -- $cfg
    ghdl -r --std=08 -frelaxed -fsynopsys --workdir="$out" sdram_linebuf_tb \
        -gCPU_MHZ="$1" -gMEM_PHASE_PS="$2" -gPOSTED_BITS="$3" -gSEED="$4" \
        --assert-level=error --ieee-asserts=disable | grep -E "PASS" \
        || { echo "FAIL line buffer + SDRAMC config $cfg"; exit 1; }
done
if ghdl -r --std=08 -frelaxed -fsynopsys --workdir="$out" sdram_linebuf_tb -gSNOOP_ON="'0'" -gOPS=2000 \
    --assert-level=error --ieee-asserts=disable > "$out/neg.log" 2>&1; then
    echo "FAIL write snooping disconnected but no stale read detected"; exit 1
fi
grep -q "read word" "$out/neg.log"
echo "PASS negative control: without write snooping a stale read is caught"
