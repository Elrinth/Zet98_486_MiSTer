#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
ghdl -a --std=08 --workdir="$w" rtl/pc98_sdip.vhd tests/sdip_tb.vhd
ghdl -e --std=08 --workdir="$w" sdip_tb
ghdl -r --std=08 --workdir="$w" sdip_tb --assert-level=error
