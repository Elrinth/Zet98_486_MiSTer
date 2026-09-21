#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
source=${1:-Zet98/Zet98MiSTer.vhd}
test "$(grep -c -- '-- BEGIN PC98 DATA BUS' "$source")" = 1
test "$(grep -c -- '-- END PC98 DATA BUS' "$source")" = 1
# Use the actual top-level expressions, not a reimplementation of the mux.
sed '$d' tests/pc98_data_bus_tb.vhd > "$out/data_bus_tb.vhd"
sed -n '/-- BEGIN PC98 DATA BUS/,/-- END PC98 DATA BUS/p' "$source" >> "$out/data_bus_tb.vhd"
cat tests/reference/pc98_data_bus_legacy.vhd.inc >> "$out/data_bus_tb.vhd"
printf 'end architecture;\n' >> "$out/data_bus_tb.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/grcg.vhd "$out/data_bus_tb.vhd"
ghdl -e --std=08 -fsynopsys --workdir="$out" pc98_data_bus_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" pc98_data_bus_tb --assert-level=error
