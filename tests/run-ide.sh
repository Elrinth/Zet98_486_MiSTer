#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -Wall -s pc98_ide_tb -o "$out/ide.vvp" rtl/storage/pc98_ide.sv rtl/storage/pc98_atapi.sv tests/pc98_ide_tb.sv
vvp "$out/ide.vvp"
