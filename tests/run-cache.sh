#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
intel_lib=${INTEL_SIM_LIB:-/project/build/intel-sim}
test -f "$intel_lib/altera_mf.v"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
nasm -f bin tests/ao486_cache.asm -o "$out/cache.bin"
sed -e "s/\.wren_a(memory_we\[i\])/\.wren_a(memory_we[i] \& 1'b1)/" \
    -e "s/\.byteena_a(memory_be)/\.byteena_a(memory_be | 4'b0)/" \
    -e "s/(CLK)/(CLK \& 1'b1)/g" rtl/vendor/cache/l1_icache.v > "$out/l1_icache.v"
sed -e "s/(clk)/(clk \& 1'b1)/g" rtl/vendor/common/simple_fifo_mlab.v > "$out/simple_fifo_mlab.v"
mapfile -t sources < <(sed -n 's@.*qip_path) \([^ ]*\.v\) .*@rtl/vendor/ao486/\1@p' rtl/vendor/ao486/ao486.qip)
iverilog -g2012 -s l1_invalidate_tb -o "$out/invalidate.vvp" \
    "$out/l1_icache.v" "$out/simple_fifo_mlab.v" tests/l1_invalidate_tb.sv \
    "$intel_lib/altera_mf.v" 2>"$out/compile.log" || { cat "$out/compile.log"; exit 1; }
vvp "$out/invalidate.vvp"
for config in ${CACHE_CONFIGS:-00 10 11}; do
    cache=${config:0:1}
    lowmem=${config:1:1}
    iverilog -g2012 -I rtl/vendor/ao486 -s ao486_cache_tb \
        -Pao486_cache_tb.ICACHE_ENABLE="$cache" -Pao486_cache_tb.LOWMEM_CACHE="$lowmem" \
        -Pao486_cache_tb.LOWMEM_CACHE_KB="${LOWMEM_CACHE_KB:-8}" -o "$out/cache.vvp" \
        "${sources[@]}" "$out/l1_icache.v" "$out/simple_fifo_mlab.v" \
        rtl/vendor/common/simple_mult.v rtl/cpu/*.sv tests/cpu_export.sv \
        tests/ao486_cache_tb.sv "$intel_lib/altera_mf.v" 2>"$out/compile.log" || { cat "$out/compile.log"; exit 1; }
    vvp "$out/cache.vvp" "+program=$out/cache.bin" "$@"
done
# Negative control: the warmed routine must stay stale if DMA invalidation is
# disconnected. This guards against a test that accidentally never hits cache.
iverilog -g2012 -I rtl/vendor/ao486 -s ao486_cache_tb \
    -Pao486_cache_tb.INVALIDATION_CONNECTED=0 -Pao486_cache_tb.LOWMEM_CACHE=1 \
    -Pao486_cache_tb.LOWMEM_CACHE_KB="${LOWMEM_CACHE_KB:-8}" -o "$out/stale.vvp" \
    "${sources[@]}" "$out/l1_icache.v" "$out/simple_fifo_mlab.v" \
    rtl/vendor/common/simple_mult.v rtl/cpu/*.sv tests/cpu_export.sv \
    tests/ao486_cache_tb.sv "$intel_lib/altera_mf.v" 2>"$out/compile.log" || { cat "$out/compile.log"; exit 1; }
if vvp "$out/stale.vvp" "+program=$out/cache.bin" "$@" >"$out/stale.log" 2>&1; then
    echo 'Disconnected DMA invalidation unexpectedly passed' >&2; exit 1
fi
grep -q 'Cache coherence/checksum failure' "$out/stale.log"
echo 'PASS: disconnected DMA invalidation fails the full-CPU coherence test'
