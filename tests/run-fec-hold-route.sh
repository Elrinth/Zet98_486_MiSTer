#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 tests/make_fec_hold_route.py "$out"
ghdl -a --std=08 --workdir="$out" tests/lcell_model.vhd "$out/fec_hold_route_probe.vhd" tests/fec_hold_route_tb.vhd
ghdl -e --std=08 --workdir="$out" fec_hold_route_tb
ghdl -r --std=08 --workdir="$out" fec_hold_route_tb --assert-level=error
# The independent word identity checker must reject a corrupted final output.
sed 's/fec_read_crossing <= fec_hold_route(4);/fec_read_crossing <= not fec_hold_route(4);/' "$out/fec_hold_route_probe.vhd" > "$out/bad-route.vhd"
ghdl -a --std=08 --workdir="$out" "$out/bad-route.vhd" tests/fec_hold_route_tb.vhd
if ghdl -r --std=08 --workdir="$out" fec_hold_route_tb --assert-level=error > "$out/negative.log" 2>&1; then
 echo 'FAIL: corrupted FEC route accepted'; exit 1
fi
grep -q 'FEC route changed payload' "$out/negative.log"
echo 'PASS FEC route corruption negative'
bash tests/run-floppy-read-bundle.sh
bash tests/run-floppy-sdram.sh
bash tests/run-sdram-control-cdc.sh
