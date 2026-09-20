#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
wrapper=${1:-Zet98/MiSTer/Zet98.sv}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
printf '`define BUILD_DATE "test"\n' > "$out/build_id.v"
# Icarus requires a default for untyped parameters. Both instances override
# CONF_STR/STRLEN; unused defaults in this temporary copy change no logic.
sed -e 's/parameter CONF_STR, STRLEN)/parameter CONF_STR = "", STRLEN = 1)/' \
    -e 's/parameter CONF_STR,/parameter CONF_STR = "",/' MiSTer/sys/hps_io.sv > "$out/hps_io.sv"
iverilog -g2012 -Wall -I "$out" -s mister_disk_interface_tb -o "$out/disk.vvp" \
    "$out/hps_io.sv" rtl/video_output.sv "$wrapper" tests/mister_disk_interface_tb.sv
vvp "$out/disk.vvp"
