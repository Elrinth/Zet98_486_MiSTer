#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
python3 tests/write_payload_equivalence.py "$out/check.sv"
iverilog -g2012 -I rtl/vendor/ao486 -s check -o "$out/check.vvp" rtl/vendor/ao486/pipeline/write_commands.v "$out/check.sv"
vvp "$out/check.vvp"
bash tests/run-cpu.sh
LOWMEM_CACHE=1 CPU_REP_COUNTS=1 bash tests/run-cpu.sh
