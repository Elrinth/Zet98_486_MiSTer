#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
run() {
 ghdl -a --std=08 -fsynopsys --workdir="$out" "$1" "$2" tests/pit_mode3_tb.vhd
 ghdl -e --std=08 -fsynopsys --workdir="$out" pit_mode3_tb
 ghdl -r --std=08 -fsynopsys --workdir="$out" pit_mode3_tb --assert-level=error --ieee-asserts=disable-at-0
}
run Zet98/PTC/PTC1ch.vhd Zet98/PTC/PTC8253.vhd
# Negative controls: mode 3 counting by 1, reads that only see the last latch,
# a latch that rewrites the mode, and control words without load semantics.
tr -d '\r' < Zet98/PTC/PTC1ch.vhd | sed 's/CURCOUNT<=CURCOUNT-x"0002";/CURCOUNT<=CURCOUNT-x"0001";/' > "$out/byone.vhd"
! cmp -s <(tr -d '\r' < Zet98/PTC/PTC1ch.vhd) "$out/byone.vhd"
if run "$out/byone.vhd" Zet98/PTC/PTC8253.vhd > "$out/neg1.log" 2>&1; then echo 'FAIL count-by-1 mode 3 accepted'; exit 1; fi
grep -q 'readback' "$out/neg1.log" || { cat "$out/neg1.log"; exit 1; }
tr -d '\r' < Zet98/PTC/PTC1ch.vhd | sed '/if(LATCHED=.0.)then$/{n;s/LATCOUNT<=CURCOUNT;/null;/}' > "$out/stale.vhd"
! cmp -s <(tr -d '\r' < Zet98/PTC/PTC1ch.vhd) "$out/stale.vhd"
if run "$out/stale.vhd" Zet98/PTC/PTC8253.vhd > "$out/neg0.log" 2>&1; then echo 'FAIL stale unlatched reads accepted'; exit 1; fi
grep -q 'readback' "$out/neg0.log" || { cat "$out/neg0.log"; exit 1; }
tr -d '\r' < Zet98/PTC/PTC8253.vhd | sed 's/CNTLAT(0)<=.1.;\t\t-- latch only: mode and BCD stay/CNTLAT(0)<='"'"'1'"'"'; OPMODE0<=WDAT(3 downto 1);/' > "$out/latch.vhd"
! cmp -s <(tr -d '\r' < Zet98/PTC/PTC8253.vhd) "$out/latch.vhd"
if run Zet98/PTC/PTC1ch.vhd "$out/latch.vhd" > "$out/neg2.log" 2>&1; then echo 'FAIL latch changing the mode accepted'; exit 1; fi
grep -q 'latch' "$out/neg2.log" || { cat "$out/neg2.log"; exit 1; }
# Control words that neither set OUT nor wait for the count: the M&M3 pattern
# gets a spurious rising edge on every reprogramming.
tr -d '\r' < Zet98/PTC/PTC1ch.vhd | sed 's/if(CTLWR=.1.)then$/if(false)then/' > "$out/nowait.vhd"
! cmp -s <(tr -d '\r' < Zet98/PTC/PTC1ch.vhd) "$out/nowait.vhd"
if run "$out/nowait.vhd" Zet98/PTC/PTC8253.vhd > "$out/neg3.log" 2>&1; then echo 'FAIL control words without load semantics accepted'; exit 1; fi
grep -q 'mode' "$out/neg3.log" || { cat "$out/neg3.log"; exit 1; }
echo 'PASS count-by-1 square wave, stale reads, mode-changing latch and immediate count bytes rejected'
