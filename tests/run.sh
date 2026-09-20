#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s ao486_io_bridge_tb -o "$out/io.vvp" \
    rtl/cpu/ao486_io_bridge.sv tests/ao486_io_bridge_tb.sv
vvp "$out/io.vvp"
