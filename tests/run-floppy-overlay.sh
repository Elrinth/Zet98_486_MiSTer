#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for bench in floppy_overlay_tb floppy_overlay_stream_tb; do
    iverilog -g2012 -Wall -s "$bench" -o "$out/overlay.vvp" rtl/floppy_overlay.sv "tests/$bench.sv"
    vvp "$out/overlay.vvp"
done
