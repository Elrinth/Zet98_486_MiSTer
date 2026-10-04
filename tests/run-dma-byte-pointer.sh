#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
root=$PWD
cd "$out"
ghdl -a --std=08 -fsynopsys "$root/Zet98/DMA/DMA1ch.vhd" "$root/Zet98/DMA/DMA8237.vhd" "$root/tests/dma_byte_pointer_tb.vhd"
ghdl -e --std=08 -fsynopsys dma_byte_pointer_tb
ghdl -r --std=08 -fsynopsys dma_byte_pointer_tb --assert-level=error
