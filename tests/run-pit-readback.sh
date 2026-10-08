#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
run() {
 ghdl -a --std=08 -fsynopsys --workdir="$out" "$1" "$2" tests/pit_readback_tb.vhd
 ghdl -e --std=08 -fsynopsys --workdir="$out" pit_readback_tb
 ghdl -r --std=08 -fsynopsys --workdir="$out" pit_readback_tb --assert-level=error --ieee-asserts=disable-at-0
}
run Zet98/PTC/PTC1ch.vhd Zet98/PTC/PTC8253.vhd
# Negative controls: reads that only ever return the last latch (the old
# PIT), and a PIT that ignores the read-back command.
tr -d '\r' < Zet98/PTC/PTC1ch.vhd | sed "s/RDCOUNT<=LATCOUNT when LATCHED='1' else CURCOUNT;/RDCOUNT<=LATCOUNT;/" > "$out/latchonly.vhd"
! cmp -s <(tr -d '\r' < Zet98/PTC/PTC1ch.vhd) "$out/latchonly.vhd"
if run "$out/latchonly.vhd" Zet98/PTC/PTC8253.vhd > "$out/neg1.log" 2>&1; then echo 'FAIL latch-only reads accepted'; exit 1; fi
grep -q 'unlatched' "$out/neg1.log" || { cat "$out/neg1.log"; exit 1; }
tr -d '\r' < Zet98/PTC/PTC8253.vhd | sed 's/CNTLAT(i)<=WDAT(i+1) and not WDAT(5);/null;/' > "$out/norb.vhd"
! cmp -s <(tr -d '\r' < Zet98/PTC/PTC8253.vhd) "$out/norb.vhd"
if run Zet98/PTC/PTC1ch.vhd "$out/norb.vhd" > "$out/neg2.log" 2>&1; then echo 'FAIL ignored read-back accepted'; exit 1; fi
grep -q 'read-back' "$out/neg2.log" || { cat "$out/neg2.log"; exit 1; }
echo 'PASS latch-only reads and ignored read-back rejected'
