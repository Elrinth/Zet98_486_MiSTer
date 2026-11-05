#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -s crash_recorder_gp_tb -o "$out/tb" rtl/cpu/z486_crash_recorder.sv tests/crash_recorder_gp_tb.sv
vvp -n "$out/tb"
