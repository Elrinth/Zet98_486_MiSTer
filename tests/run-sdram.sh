#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/sdramc.vhd tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
for mhz in 20 40 50 60; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb -gCPU_MHZ="$mhz" --assert-level=error
done
