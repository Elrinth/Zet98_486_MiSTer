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
# Reintroduce the old enable-gated timer-B clear. The checker must reject it,
# not merely observe a timer that never happened to overflow in the test.
mkdir "$out/negative"
sed "s/if(TBRST='1')then/if(sft='1' and TBRST='1')then/" \
    "${OPNA_SOURCE:-sound/OPN/OPNA.vhd}" > "$out/negative/OPNA.vhd"
ghdl -a --std=08 -fsynopsys --workdir="$out/negative" sound/FMcommon/envelope_pkg.vhd \
    "$out/negative/OPNA.vhd" tests/opna_timer_tb.vhd
ghdl -e --std=08 -fsynopsys -Wno-binding --workdir="$out/negative" opna_timer_tb
if ghdl -r --std=08 -fsynopsys -Wno-binding --workdir="$out/negative" opna_timer_tb \
    -gDIVISOR=5 --assert-level=error --ieee-asserts=disable > "$out/negative.log" 2>&1; then
    echo 'FAIL: enable-gated FM timer clear unexpectedly passed' >&2
    exit 1
fi
grep -q 'timer B clear lost' "$out/negative.log"
echo 'PASS: lost FM timer-clear negative control rejected'
