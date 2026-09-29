#!/usr/bin/env bash
# Posted CPU word writes through the real SDRAM controller and a storing SDRAM
# model: random writes/reads checked against program order (GHDL 4.x).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" tests/lcell_model.vhd Zet98/sdramc.vhd tests/sdram_posted_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_posted_tb
for cfg in "90 0 3" "90 2500 3" "90 7300 3" "50 0 3" "100 4100 3" "90 1300 1" "90 0 2" "90 6100 2" "90 0 0"; do
    set -- $cfg
    ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_posted_tb \
        -gCPU_MHZ="$1" -gMEM_PHASE_PS="$2" -gPOSTED_BITS="$3" --assert-level=error \
        | grep -E "PASS|FAIL|failure" || { echo "FAIL posted config $cfg"; exit 1; }
done
