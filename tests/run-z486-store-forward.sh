#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
compile() {
    verilator --binary --timing -j 2 -Wno-fatal -Wno-WIDTH -Wno-PINMISSING -Wno-TIMESCALEMOD \
        -Irtl/vendor/z486 --Mdir "$out/$1" --top-module z486_store_forward_tb \
        rtl/vendor/z486/z486_cache_map_pkg.sv "$2" tests/z486_store_forward_tb.sv \
        > "$out/compile-$1.log" 2>&1 || { tail -n 30 "$out/compile-$1.log"; exit 1; }
}
compile good rtl/vendor/z486/l1_cache.sv
"$out/good/Vz486_store_forward_tb"
# A forward with a missing byte must disagree with the retained per-slot model.
sed 's/req_forward_mask);/(req_forward_mask \& 4\x27he));/' \
    rtl/vendor/z486/l1_cache.sv > "$out/bad.sv"
compile bad "$out/bad.sv"
if "$out/bad/Vz486_store_forward_tb" > "$out/bad.log" 2>&1; then
    echo 'FAIL: missing-byte forwarding mutation passed'; exit 1
fi
grep -q 'storeq lookup forward mismatch' "$out/bad.log"
echo 'PASS: missing-byte forwarding mutation rejected'
