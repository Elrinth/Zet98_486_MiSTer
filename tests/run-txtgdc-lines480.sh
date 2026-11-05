#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" Zet98/GDC/txtgdc.vhd tests/txtgdc_lines480_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" txtgdc_lines480_tb
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" txtgdc_lines480_tb --assert-level=error --ieee-asserts=disable-at-0
