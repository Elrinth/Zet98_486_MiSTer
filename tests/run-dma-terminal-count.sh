#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
cd "$out"
ghdl -a --std=08 -fsynopsys "$root/Zet98/DMA/DMA1ch.vhd" "$root/tests/dma_terminal_count_tb.vhd"
ghdl -e --std=08 -fsynopsys dma_terminal_count_tb
ghdl -r --std=08 -fsynopsys dma_terminal_count_tb --assert-level=error
