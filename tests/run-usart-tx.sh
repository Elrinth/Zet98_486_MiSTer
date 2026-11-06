#!/usr/bin/env bash
# The RS-232C 8251 clocked by PIT channel 2 (usart_tx_tb.vhd), then the negative
# control: with TxC/RxC tied off, as before, TxRDY must never come back.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
src="LIB/sftdiv.vhd LIB/PARITYG.vhd LIB/g_srff.vhd USART/txframe.vhd USART/rxframe.vhd USART/e8251.vhd
     Zet98/PTC/PTC1ch.vhd Zet98/PTC/PTC8253.vhd tests/usart_tx_tb.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" $src
ghdl -e --std=08 -fsynopsys --workdir="$out" usart_tx_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" usart_tx_tb --assert-level=error > "$out/pass.log" 2>&1 || { cat "$out/pass.log"; exit 1; }
grep -q 'usart_tx_tb done' "$out/pass.log" || { cat "$out/pass.log"; exit 1; }
echo 'PASS: 8251 on PIT channel 2 sends and returns TxRDY'

if ghdl -r --std=08 -fsynopsys --workdir="$out" usart_tx_tb -gCLOCKED=false --assert-level=error > "$out/negative.log" 2>&1; then
    echo 'FAIL: TxRDY returned with the clocks tied off' >&2; exit 1
fi
grep -q 'TxRDY did not return' "$out/negative.log" || { cat "$out/negative.log"; exit 1; }
echo 'PASS: clocks tied off (B279) never return TxRDY'
