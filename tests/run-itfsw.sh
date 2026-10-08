#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$w" Zet98/itfsw.vhd tests/itfsw_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$w" itfsw_tb
ghdl -r --std=08 -fsynopsys --workdir="$w" itfsw_tb --assert-level=error
