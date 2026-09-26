#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for seed in 1 19 937; do
    iverilog -g2012 -Wall -s pc98_pegc_ddr_tb -Ppc98_pegc_ddr_tb.SEED="$seed" -o "$out/ddr" \
        rtl/graphics/pc98_pegc_memory.sv rtl/graphics/pc98_pegc_ddr_arbiter.sv tests/pc98_pegc_ddr_tb.sv
    vvp "$out/ddr"
done
# An arbiter that loses its response tag on guest reset must fail.
sed 's/grant_valid<=0; next_client<=0;/grant_valid<=0; next_client<=0; remaining<=0;/' \
    rtl/graphics/pc98_pegc_ddr_arbiter.sv > "$out/broken.sv"
iverilog -g2012 -s pc98_pegc_ddr_tb -o "$out/negative" \
    rtl/graphics/pc98_pegc_memory.sv "$out/broken.sv" tests/pc98_pegc_ddr_tb.sv
if vvp "$out/negative" > "$out/negative.log" 2>&1; then
    echo 'FAIL: erased outstanding DDR tag accepted';exit 1
fi
grep -Eq 'response fanout/loss|command overtook read response|late response reached wrong owner' "$out/negative.log" || { cat "$out/negative.log";exit 1; }
echo 'PASS: lost DDR response tag negative control rejected'
