#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -s hdmi_tune_gate_tb -o "$out/test" rtl/hdmi_tune_gate.sv tests/hdmi_tune_gate_tb.sv
vvp "$out/test"
# Original all-bit gating must fail when configuration changes mid-clock.
sed 's/raw_tune\[7:6\],/raw_tune[7:6] \& {2{enable}},/' rtl/hdmi_tune_gate.sv > "$out/gated-clocks.sv"
iverilog -g2012 -s hdmi_tune_gate_tb -o "$out/negative" "$out/gated-clocks.sv" tests/hdmi_tune_gate_tb.sv
if vvp "$out/negative" > "$out/negative.log" 2>&1; then
    echo 'FAIL: configuration-gated measurement clocks accepted';exit 1
fi
grep -q 'configuration generated or suppressed a measurement clock edge' "$out/negative.log"
echo 'PASS: clock gating by configuration rejected'
