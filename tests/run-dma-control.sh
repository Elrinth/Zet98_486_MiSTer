#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
sed '$d' tests/dma_control_tb.vhd > "$w/test.vhd"
sed -n '/-- BEGIN PC98 DMA CONTROL READBACK/,/-- END PC98 DMA CONTROL READBACK/p' Zet98/Zet98MiSTer.vhd >> "$w/test.vhd"
echo 'end;' >> "$w/test.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$w" Zet98/IO_WR.vhd Zet98/IO_RD.vhd "$w/test.vhd"
ghdl -e --std=08 -fsynopsys --workdir="$w" dma_control_tb
for cpu in 0 1 2; do
    ghdl -r --std=08 -fsynopsys --workdir="$w" dma_control_tb -gCPU486="$cpu" --assert-level=error
done
