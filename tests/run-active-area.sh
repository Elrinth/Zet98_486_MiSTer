#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" VIDEO/synccont2.vhd tests/active_area_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" active_area_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" active_area_tb --assert-level=error --ieee-asserts=disable-at-0
