#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" Zet98/KBIF/KBCONV.vhd Zet98/z8259.vhd tests/kbconv_backpressure_tb.vhd tests/kbconv_pic_eoi_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" kbconv_pic_eoi_tb
for delay in 0 8 16 64 256; do
 for ack in 1 4; do
  ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" kbconv_pic_eoi_tb -gEOI_DELAY=$delay -gACK_CYCLES=$ack --assert-level=error --ieee-asserts=disable-at-0
 done
done
