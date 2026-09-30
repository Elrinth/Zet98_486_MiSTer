#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -frelaxed -fsynopsys --workdir="$out" Zet98/mainram_linebuf.vhd tests/mainram_linebuf_tb.vhd
ghdl -e --std=08 -frelaxed -fsynopsys --workdir="$out" mainram_linebuf_tb
for seed in 1 7 42; do
 ghdl -r --std=08 -frelaxed -fsynopsys --workdir="$out" mainram_linebuf_tb -gSEED=$seed --assert-level=error --ieee-asserts=disable-at-0
done
if ghdl -r --std=08 -frelaxed -fsynopsys --workdir="$out" mainram_linebuf_tb -gSNOOP=false --assert-level=error --ieee-asserts=disable-at-0 > "$out/neg.log" 2>&1; then
 echo 'FAIL write snooping disconnected but no stale read detected'; exit 1
fi
grep -q 'stale/wrong read' "$out/neg.log"
echo 'PASS negative control: without write snooping a stale read is caught'
if ghdl -r --std=08 -frelaxed -fsynopsys --workdir="$out" mainram_linebuf_tb -gEGCMASK=false --assert-level=error --ieee-asserts=disable-at-0 > "$out/egc.log" 2>&1; then
 echo 'FAIL raw acknowledge (EGC acknowledges visible to the buffer) was accepted'; exit 1
fi
grep -q -E 'deadlock|stale/wrong read' "$out/egc.log"
echo "PASS negative control: raw CB_ACK during EGC work caught ($(grep -o -E 'deadlock|stale/wrong read' "$out/egc.log" | head -1))"
