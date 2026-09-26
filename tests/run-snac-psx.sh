#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s snac_psx_pad_tb -o "$out/sim" rtl/snac_psx_pad.sv tests/snac_psx_pad_tb.sv
vvp "$out/sim"
# Negative controls: MSB-first bit order and swapped port selects must fail.
for mutation in msb swapped; do
  case "$mutation" in
    msb) sed 's/rx <= {dat_sync\[1\], rx\[7:1\]}/rx <= {rx[6:0], dat_sync[1]}/' rtl/snac_psx_pad.sv > "$out/bad.sv" ;;
    swapped) sed 's/port ? 1.b1 : att, port ? att : 1.b1/port ? att : 1'"'"'b1, port ? 1'"'"'b1 : att/' rtl/snac_psx_pad.sv > "$out/bad.sv" ;;
  esac
  ! cmp -s rtl/snac_psx_pad.sv "$out/bad.sv"
  iverilog -g2012 -s snac_psx_pad_tb -o "$out/bad" "$out/bad.sv" tests/snac_psx_pad_tb.sv
  if vvp "$out/bad" > "$out/bad.log" 2>&1; then echo "FAIL: $mutation accepted"; exit 1; fi
  echo "PASS: $mutation mutation rejected"
done
