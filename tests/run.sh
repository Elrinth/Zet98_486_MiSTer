#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s ao486_io_bridge_tb -o "$out/io.vvp" \
    rtl/cpu/ao486_io_bridge.sv tests/ao486_io_bridge_tb.sv
vvp "$out/io.vvp"
ghdl -a --std=08 -fsynopsys --workdir="$out" \
    LIB/sftgen.vhd LIB/sftclk.vhd LIB/fixtimer.vhd tests/peripheral_rates_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" peripheral_rates_tb --assert-level=error
