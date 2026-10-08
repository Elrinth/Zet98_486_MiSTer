#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$w" Zet98/mem_addr_pkg_MiSTer.vhd Zet98/memorymap.vhd rtl/pc98_rombank.vhd tests/rombank_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$w" rombank_tb
ghdl -r --std=08 -fsynopsys --workdir="$w" rombank_tb --assert-level=error
