#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sed 's/module decode_regs(/module decode_regs_legacy(/' tests/reference/decode_regs_legacy.v > "$out/legacy.v"
iverilog -g2012 -s decode_regs_tb -o "$out/test" rtl/vendor/ao486/pipeline/decode_regs.v "$out/legacy.v" tests/decode_regs_tb.sv
vvp "$out/test"
sed 's/consume_enabled ? consume_step : stalled_step/consume_step/' rtl/vendor/ao486/pipeline/decode_regs.v > "$out/ignored-stall.v"
iverilog -g2012 -s decode_regs_tb -o "$out/negative" "$out/ignored-stall.v" "$out/legacy.v" tests/decode_regs_tb.sv
if vvp "$out/negative" > "$out/negative.log" 2>&1; then
    echo 'FAIL: ignored consume stall accepted';exit 1
fi
grep -q 'decode buffer differs' "$out/negative.log"
echo 'PASS: ignored decode stall rejected'
