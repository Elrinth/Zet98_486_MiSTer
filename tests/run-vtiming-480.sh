#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys -fexplicit --workdir="$out" VIDEO/video_timing_pkg.vhd VIDEO/VTIMING.vhd tests/vtiming_480_tb.vhd
ghdl -e --std=08 -fsynopsys -fexplicit --workdir="$out" vtiming_480_tb
ghdl -r --std=08 -fsynopsys -fexplicit --workdir="$out" vtiming_480_tb
