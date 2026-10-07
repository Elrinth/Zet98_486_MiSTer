#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
ghdl -a --std=08 --workdir="$w" rtl/storage/pc98_floppy_events.vhd tests/floppy_events_tb.vhd
ghdl -e --std=08 --workdir="$w" floppy_events_tb
ghdl -r --std=08 --workdir="$w" floppy_events_tb --assert-level=error
