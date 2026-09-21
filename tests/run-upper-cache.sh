#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
intel_lib=${INTEL_SIM_LIB:-/project/build/intel-sim}
test -f "$intel_lib/altera_mf.v"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/ao486_upper_cache.asm -o "$out/program.bin"
# Simulate the same VHDL policy used by the FPGA, translated by GHDL.
ghdl --synth --std=08 --out=verilog -gUPPER_RAM_ICACHE=1 rtl/cpu/pc98_cache_policy.vhd -e pc98_cache_policy > "$out/policy.v"
sed -e "s/\.wren_a(memory_we\[i\])/\.wren_a(memory_we[i] \& 1'b1)/" \
    -e "s/\.byteena_a(memory_be)/\.byteena_a(memory_be | 4'b0)/" \
    -e "s/(CLK)/(CLK \& 1'b1)/g" rtl/vendor/cache/l1_icache.v > "$out/l1_icache.v"
sed -e "s/(clk)/(clk \& 1'b1)/g" rtl/vendor/common/simple_fifo_mlab.v > "$out/simple_fifo_mlab.v"
mapfile -t sources < <(sed -n 's@.*qip_path) \([^ ]*\.v\) .*@rtl/vendor/ao486/\1@p' rtl/vendor/ao486/ao486.qip)
for config in 0:0 1:0 1:1 1:2 1:3; do
    upper=${config%:*}
    skip=${config#*:}
    iverilog -g2012 -I rtl/vendor/ao486 -s ao486_upper_cache_tb \
        -Pao486_upper_cache_tb.UPPER_RAM_ICACHE="$upper" \
        -Pao486_upper_cache_tb.SKIP_INVALIDATION="$skip" -o "$out/upper.vvp" \
        "${sources[@]}" "$out/l1_icache.v" "$out/simple_fifo_mlab.v" "$out/policy.v" \
        rtl/vendor/common/simple_mult.v rtl/cpu/*.sv tests/cpu_export.sv \
        tests/ao486_upper_cache_tb.sv "$intel_lib/altera_mf.v" 2>"$out/compile.log" || { cat "$out/compile.log"; exit 1; }
    if [ "$skip" = 0 ]; then
        vvp "$out/upper.vvp" "+program=$out/program.bin" | tee "$out/run-$upper.log"
    else
        if vvp "$out/upper.vvp" "+program=$out/program.bin" > "$out/negative.log" 2>&1; then
            echo "FAIL: disconnected invalidation $skip was accepted"; exit 1
        fi
        grep -q 'Upper RAM cache coherence failure' "$out/negative.log"
        echo "PASS: disconnected invalidation $skip rejected (1 alias / 2 DMA / 3 mapping)"
    fi
done
python3 - "$out" <<'PY'
import pathlib, re, sys
out = pathlib.Path(sys.argv[1])
results = [tuple(map(int, re.search(r'cycles=(\d+) upper_fetches=(\d+)',
           (out / f'run-{i}.log').read_text()).groups())) for i in (0, 1)]
assert results[1][0] < results[0][0], results
assert results[1][1] * 10 < results[0][1], results
print(f'PASS: upper RAM loop {results[0][0]} -> {results[1][0]} cycles; '
      f'{results[0][1]} -> {results[1][1]} upper instruction bus reads')
PY
