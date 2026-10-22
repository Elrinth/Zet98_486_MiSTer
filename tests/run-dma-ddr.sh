#!/usr/bin/env bash
# DMA cycles above 1 MB share the DDR port with the CPU (rtl/cpu/pc98_dma_ddr.sv).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for seed in 1 2 3 4 5; do
    iverilog -g2012 -Wall -s pc98_dma_ddr_tb -Ppc98_dma_ddr_tb.SEED="$seed" \
        -o "$out/dma.vvp" rtl/cpu/pc98_dma_ddr.sv tests/pc98_dma_ddr_tb.sv
    vvp -n "$out/dma.vvp"
done
# Negative control: granting the slot while a CPU read is outstanding must fail.
sed 's/cpu_remaining_next==0) dma_grant <= 1;/1) dma_grant <= 1;/' rtl/cpu/pc98_dma_ddr.sv > "$out/broken.sv"
! grep -q "cpu_remaining_next==0) dma_grant" "$out/broken.sv"
iverilog -g2012 -s pc98_dma_ddr_tb -o "$out/broken.vvp" "$out/broken.sv" tests/pc98_dma_ddr_tb.sv
if vvp -n "$out/broken.vvp" > "$out/broken.log" 2>&1; then
    echo "FAIL: broken arbiter passed"; exit 1
fi
echo "negative control failed as expected"
