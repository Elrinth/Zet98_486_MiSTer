#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s boot_media_control_tb -o "$out/control.vvp" rtl/boot_media_control.sv tests/boot_media_control_tb.sv
vvp "$out/control.vvp"
iverilog -g2012 -Wall -s video_output_tb -o "$out/video.vvp" rtl/video_output.sv tests/video_output_tb.sv
vvp "$out/video.vvp"
iverilog -g2012 -Wall -s boot_prompt_tb -o "$out/prompt.vvp" rtl/video_output.sv tests/boot_prompt_tb.sv
vvp "$out/prompt.vvp" "+output=$out"
python3 tests/verify_boot_prompt.py "$out"
