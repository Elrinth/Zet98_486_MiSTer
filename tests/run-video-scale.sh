#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s video_scale_int_tb -o "$out/scale.vvp" MiSTer/sys/math.sv MiSTer/sys/video_freak.sv tests/video_scale_int_tb.sv
vvp "$out/scale.vvp"
