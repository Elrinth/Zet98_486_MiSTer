#!/usr/bin/env bash
# PS2DIRECT unit test (keyboard and mouse byte streams from hps_io events),
# then the real KBCONV through it (make/break/extended, LED init handshake).
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" PS2IF/PS2DIRECT.vhd tests/ps2direct_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" ps2direct_tb
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" ps2direct_tb --assert-level=error --ieee-asserts=disable-at-0
mkdir -p "$out/kb"
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out/kb" PS2IF/PS2DIRECT.vhd Zet98/KBIF/KBCONV.vhd tests/kbconv_direct_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out/kb" kbconv_direct_tb
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out/kb" kbconv_direct_tb --assert-level=error --ieee-asserts=disable-at-0
