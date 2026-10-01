#!/usr/bin/env bash
# Posted four-plane GRCG writes (WR4, RMW4) through the real SDRAM controller
# against a storing burst model; RD4 reads checked in program order. FIFO 0 = unposted reference.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" tests/lcell_model.vhd Zet98/sdramc.vhd tests/sdram_posted4_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_posted4_tb
for cfg in "90 0 0" "90 0 2" "90 2500 2" "90 7300 2" "50 0 2" "100 4100 2" "90 1300 1" "90 6100 3"; do
    set -- $cfg
    ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_posted4_tb \
        -gCPU_MHZ="$1" -gMEM_PHASE_PS="$2" -gPOSTED_BITS="$3" --assert-level=error \
        | grep -E "PASS|FAIL|failure" || { echo "FAIL posted4 config $cfg"; exit 1; }
done
# Negative control: draining every queued job as a plain word write must fail.
sed 's/when PW_WR4 => STATE<=ST_WRITE4;/when PW_WR4 => STATE<=ST_WRITE;/' Zet98/sdramc.vhd > "$out/bad.vhd"
! cmp -s Zet98/sdramc.vhd "$out/bad.vhd"
mkdir "$out/bad"
ghdl -a --std=08 -fsynopsys --workdir="$out/bad" tests/lcell_model.vhd "$out/bad.vhd" tests/sdram_posted4_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out/bad" sdram_posted4_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out/bad" sdram_posted4_tb --assert-level=error > "$out/bad.log" 2>&1; then
    echo "FAIL: posted WR4 drained as a word write accepted"; exit 1
fi
echo "PASS: posted WR4 drained as a word write rejected"
