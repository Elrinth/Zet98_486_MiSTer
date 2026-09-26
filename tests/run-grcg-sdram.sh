#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" tests/lcell_model.vhd Zet98/grcg.vhd Zet98/sdramc.vhd tests/grcg_sdram_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" grcg_sdram_tb
for mhz in 20 50 60 90 100; do
    for phase in 0 4700; do
        for drawing in false true; do
            ghdl -r --std=08 -fsynopsys --workdir="$out" grcg_sdram_tb \
                -gBUFFERED=true -gCPU_MHZ="$mhz" -gMEM_PHASE_PS="$phase" -gUSE_SUB="$drawing" --assert-level=error
        done
    done
done
