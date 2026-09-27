#!/usr/bin/env bash
# Analog-stick mouse: stick_mouse curve/axes, MOUSECONV extra-input path, and
# SNAC right-stick/mouse-button reporting (in run-snac-psx.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s stick_mouse_tb -o "$out/stick" rtl/stick_mouse.sv tests/stick_mouse_tb.sv
vvp "$out/stick"
ghdl -a --std=08 -fsynopsys --workdir="$out" PS2IF/PS2IF.vhd LIB/sftclk.vhd Zet98/MOUSE/MOUSECONV.vhd tests/mouseconv_ext_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" mouseconv_ext_tb
ghdl -r --std=08 -fsynopsys --workdir="$out" mouseconv_ext_tb --assert-level=error 2>&1 | grep -E "PASS|FAIL|error" 
# Negative control: dropping the Y inversion must fail.
sed 's/tmp:=tmp-(extY(7) \& extY(7) \& extY);/tmp:=tmp+(extY(7) \& extY(7) \& extY);/' Zet98/MOUSE/MOUSECONV.vhd > "$out/bad.vhd"
! cmp -s Zet98/MOUSE/MOUSECONV.vhd "$out/bad.vhd"
mkdir -p "$out/bad"
ghdl -a --std=08 -fsynopsys --workdir="$out/bad" PS2IF/PS2IF.vhd LIB/sftclk.vhd "$out/bad.vhd" tests/mouseconv_ext_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out/bad" mouseconv_ext_tb
if ghdl -r --std=08 -fsynopsys --workdir="$out/bad" mouseconv_ext_tb --assert-level=error > "$out/bad.log" 2>&1; then
  echo "FAIL: inverted Y accepted"; exit 1
fi
echo "PASS: inverted-Y negative control rejected"
