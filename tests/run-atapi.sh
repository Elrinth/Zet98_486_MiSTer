#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s atapi_tb -o "$out/atapi" rtl/storage/pc98_atapi.sv tests/atapi_tb.sv
vvp "$out/atapi" +raw=0
vvp "$out/atapi" +raw=1
# 256 raw sectors are also divisible by 2048: the sync-pattern probe must win.
vvp "$out/atapi" +raw=1 +sectors=256
vvp "$out/atapi" +raw=0 +sectors=256
vvp "$out/atapi" +pcd=1
# Large discs: LBAs above 4095 (20-bit LBA from CDB bytes 3-5).
vvp "$out/atapi" +raw=0 +sectors=270000
vvp "$out/atapi" +raw=1 +sectors=70000
iverilog -g2012 -s ide_cd_tb -o "$out/idecd" rtl/storage/pc98_ide.sv rtl/storage/pc98_atapi.sv tests/ide_cd_tb.sv
vvp "$out/idecd"
