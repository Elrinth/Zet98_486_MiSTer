#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" LIB/sftgen.vhd rtl/opna_clock_enable.vhd LIB/sftclk.vhd LIB/fixtimer.vhd tests/peripheral_rates_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb
for khz in 40000 50000 60000 75000 90000 100000; do
    ghdl -r --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb -gFAST_KHZ=$khz --assert-level=error
done
# The old integer divider must fail the 75 MHz frequency comparison.
mkdir "$out/mutant"
sed 's/entity work.opna_clock_enable generic map(FAST_KHZ) port map(opn40, clk40, rstn)/entity work.sftgen generic map(FAST_KHZ\/10000) port map(FAST_KHZ\/10000, opn40, clk40, rstn)/' tests/peripheral_rates_tb.vhd > "$out/mutant.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out/mutant" LIB/sftgen.vhd LIB/sftclk.vhd LIB/fixtimer.vhd "$out/mutant.vhd"
ghdl -e --std=08 -fsynopsys --workdir="$out/mutant" peripheral_rates_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out/mutant" peripheral_rates_tb -gFAST_KHZ=75000 --assert-level=error > "$out/mutant.log" 2>&1; then
    echo "FAIL: old 75 MHz OPNA divider escaped the frequency test"
    exit 1
fi
grep -q "OPNA clock-enable frequency changed" "$out/mutant.log"
echo "PASS: old 75 MHz FM divider rejected"
bash tests/run-pcm86.sh
