#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
intel_lib=${INTEL_SIM_LIB:-/project/build/intel-sim}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
sed -e "s/(clk)/(clk \& 1'b1)/g" rtl/vendor/common/simple_fifo_mlab.v > "$out/fifo.v"
run() {
    iverilog -g2012 -I rtl/vendor/ao486 -s prefetch_store_tb -o "$out/test.vvp" \
        tests/prefetch_store_tb.sv rtl/vendor/ao486/memory/prefetch_fifo.v \
        "$1" "$intel_lib/altera_mf.v"
    vvp "$out/test.vvp"
}
run "$out/fifo.v"
# Without spare physical slots a rejected full store corrupts live data.
sed 's/pointer_width = widthu + speculative_store/pointer_width = widthu/' \
    "$out/fifo.v" > "$out/broken.v"
if run "$out/broken.v" > "$out/negative.log" 2>&1; then
    echo 'ERROR: missing-slot negative control unexpectedly passed' >&2
    exit 1
fi
grep -q 'Queue mismatch' "$out/negative.log"
echo 'PASS: missing-spare-slot negative control fails as expected'
