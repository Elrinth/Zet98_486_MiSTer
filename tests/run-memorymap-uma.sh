#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/mem_addr_pkg_MiSTer.vhd Zet98/memorymap.vhd tests/memorymap_uma_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" memorymap_uma_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" memorymap_uma_tb --assert-level=error --ieee-asserts=disable-at-0
