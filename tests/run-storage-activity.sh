#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 scripts/make_activity_rom.py --check
iverilog -g2012 -Wall -s storage_activity_tb -o "$out/activity" rtl/storage_activity.sv tests/storage_activity_tb.sv
vvp "$out/activity"
