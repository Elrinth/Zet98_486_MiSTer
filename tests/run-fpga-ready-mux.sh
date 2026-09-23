#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sed 's/module decode_regs(/module decode_regs_legacy(/' tests/reference/decode_regs_legacy.v > "$out/legacy.v"
iverilog -g2012 -DZET98_CYCLONEV_READY_MUX -Pdecode_regs_tb.COUNT_STRIDE=5 -s decode_regs_tb -o "$out/fpga" rtl/vendor/ao486/pipeline/decode_regs.v "$out/legacy.v" tests/decode_regs_tb.sv "$INTEL_SIM_LIB/cyclonev_atoms.v"
vvp "$out/fpga"
bash tests/run-cpu.sh
LOWMEM_CACHE=1 CPU_REP_COUNTS=1 bash tests/run-cpu.sh
