#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" sound/FMcommon/envelope_pkg.vhd \
    "${OPNA_SOURCE:-sound/OPN/OPNA.vhd}" tests/opna_timer_tb.vhd
ghdl -e --std=08 -fsynopsys -Wno-binding --workdir="$out" opna_timer_tb
for divisor in 2 4 5 6; do
    ghdl -r --std=08 -fsynopsys -Wno-binding --workdir="$out" opna_timer_tb \
        -gDIVISOR="$divisor" --assert-level=error --ieee-asserts=disable
done
