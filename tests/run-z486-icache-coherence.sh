#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
cd "$(dirname "$0")/.."
out=${ICACHE_COHERENCE_OUT:-}
if [[ -z $out ]]; then out=$(mktemp -d); trap 'rm -rf "$out"' EXIT; fi
mkdir -p "$out"
out=$(cd "$out"; pwd)
for bits in 7 8 9; do
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
        -Irtl/vendor/z486 --Mdir "$out/obj-$bits" --top-module z486_icache_snoop_fill_tb \
        "-GSET_BITS=$bits" rtl/vendor/z486/l1_icache.sv tests/z486_icache_snoop_fill_tb.sv \
        > "$out/compile-$bits.log" 2>&1 || { tail -n 40 "$out/compile-$bits.log"; exit 1; }
    for dma in 0 1; do
        for way in 0 1; do
            for read_collision in 0 1; do
                log="$out/run-$bits-$dma-$way-$read_collision.log"
                "$out/obj-$bits/Vz486_icache_snoop_fill_tb" "+dma=$dma" "+other_way=$way" \
                    "+read_collision=$read_collision" > "$log" 2>&1 || { cat "$log"; exit 1; }
                grep '^PASS:' "$log"
            done
        done
    done
done
