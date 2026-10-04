#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for test in pcm86_tb pcm86_rates_tb pcm86_driver_refill_tb; do
    iverilog -g2012 -Wall -s "$test" -o "$out/test.vvp" rtl/pcm86.sv "tests/$test.sv"
    vvp "$out/test.vvp"
done
