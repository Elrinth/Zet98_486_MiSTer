#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -s pc98_cpu_speed_tb -o "$out/test" rtl/vendor/z486/cpu_throttle.sv tests/pc98_cpu_speed_tb.sv
vvp "$out/test"
