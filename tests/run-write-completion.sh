#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
bash tests/run-memory-mask-contract.sh
bash tests/run-native-ddr.sh
# A write must not complete after just the first of its two halfwords.
# Reuse the byte-addressed bus model, including delayed ACK release.
sed 's/write_request \&\& last_half \&\& remaining == 1/write_request/' \
    rtl/cpu/ao486_memory_bridge.sv > "$out/early.sv"
iverilog -g2012 -s ao486_memory_bridge_tb -o "$out/early" \
    "$out/early.sv" tests/ao486_memory_bridge_tb.sv
if vvp "$out/early" > "$out/early.log" 2>&1; then
    echo 'FAIL: first-half write-completion mutation passed'; exit 1
fi
grep -Eq 'write completed before all selected bytes|duplicate/unowned write completion' "$out/early.log"
echo 'PASS: first-half write-completion mutation rejected'
