#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -s cd_trace_tb -o "$out/sim" rtl/storage/pc98_cd_trace.sv tests/cd_trace_tb.sv
vvp "$out/sim" | grep -E 'PASS|FATAL'
