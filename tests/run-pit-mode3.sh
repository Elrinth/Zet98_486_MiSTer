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
# Negative controls: the old low-first square wave, and a latch that rewrites the mode.
tr -d '\r' < Zet98/PTC/PTC1ch.vhd | sed 's/if(CURCOUNT>HALFVAL or CURCOUNT=x"0000")then/if(CURCOUNT<HALFVAL)then/' > "$out/lowfirst.vhd"
! cmp -s <(tr -d '\r' < Zet98/PTC/PTC1ch.vhd) "$out/lowfirst.vhd"
if run "$out/lowfirst.vhd" Zet98/PTC/PTC8253.vhd > "$out/neg1.log" 2>&1; then echo 'FAIL low-first mode 3 accepted'; exit 1; fi
grep -q 'mode 3' "$out/neg1.log" || { cat "$out/neg1.log"; exit 1; }
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
# Count 0 (65536) read as a low output at the start of each period: Farland
# Story's FMP tempo timer got an IRQ0 edge right after every reload.
tr -d '\r' < Zet98/PTC/PTC1ch.vhd | sed 's/if(CURCOUNT>HALFVAL or CURCOUNT=x"0000")then/if(CURCOUNT>HALFVAL)then/' > "$out/count0.vhd"
! cmp -s <(tr -d '\r' < Zet98/PTC/PTC1ch.vhd) "$out/count0.vhd"
if run "$out/count0.vhd" Zet98/PTC/PTC8253.vhd > "$out/neg4.log" 2>&1; then echo 'FAIL count 0 starting low accepted'; exit 1; fi
grep -q 'count 0' "$out/neg4.log" || { cat "$out/neg4.log"; exit 1; }
# BCD borrow setting the lower digit to 0 instead of 9.
tr -d '\r' < Zet98/PTC/PTC1ch.vhd | sed 's/-x"1") & x"9";/-x"1") \& x"0";/' > "$out/bcd.vhd"
! cmp -s <(tr -d '\r' < Zet98/PTC/PTC1ch.vhd) "$out/bcd.vhd"
if run "$out/bcd.vhd" Zet98/PTC/PTC8253.vhd > "$out/neg5.log" 2>&1; then echo 'FAIL BCD borrow to 0 accepted'; exit 1; fi
grep -q 'BCD' "$out/neg5.log" || { cat "$out/neg5.log"; exit 1; }
echo 'PASS old low-first square wave, mode-changing latch, immediate count bytes, count 0 starting low and BCD borrow to 0 rejected'
