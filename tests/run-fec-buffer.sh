#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
grep -q 'outdata_reg_b => "CLOCK1"' diskemu_mister/fecbuf.vhd
ghdl -a --std=08 -fsynopsys --workdir="$out" diskemu_mister/FECcont.vhd tests/fec_buffer_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" fec_buffer_tb
for mhz in 20 40 50 60 90 100; do
    for phase in 0 1300 4700 9100; do
        ghdl -r --std=08 -fsynopsys --workdir="$out" fec_buffer_tb -gCPU_MHZ="$mhz" -gRAM_PHASE_PS="$phase" --assert-level=error
    done
done
if ghdl -r --std=08 -fsynopsys --workdir="$out" fec_buffer_tb -gBAD_EXTRA_LATENCY=true --assert-level=error > "$out/negative.log" 2>&1; then
    echo 'FAIL: stale buffer data accepted';exit 1
fi
grep -q 'buffer write data mismatch' "$out/negative.log"
echo 'PASS: stale FEC buffer data rejected'
