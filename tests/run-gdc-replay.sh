#!/usr/bin/env bash
# Replay a logged graphics-GDC command stream (default: Totsugeki! Bakkon Street menu) into GRAGDC.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" LIB/div.vhd LIB/multi.vhd LIB/MATH/sqrt.vhd Zet98/GDC/calccircle.vhd Zet98/GDC/gragdc.vhd tests/gdc_replay_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_replay_tb
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" gdc_replay_tb -gSTREAM="${1:-tests/data_totsugeki_gdc.txt}" -gWLOG="${2:-$out/writes.txt}" --assert-level=failure --ieee-asserts=disable-at-0 2>&1 | grep -v "^$" | tail -40
