#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
mapfile -t rtl < <(find rtl/vendor/jt08/jt12/hdl rtl/vendor/jt08/jt49/hdl -name '*.v' -print | sort)
for khz in 75000 90000 100000; do
    verilator --binary --timing -Wno-fatal --top-module opna_jt08_tb \
        -GKHZ="$khz" --Mdir "$out/obj$khz" -j 1 \
        "${rtl[@]}" rtl/opna_jt08.sv tests/opna_jt08_tb.sv > "$out/compile$khz.log" 2>&1 || \
        { cat "$out/compile$khz.log"; exit 1; }
    "$out/obj$khz/Vopna_jt08_tb"
done
# A deliberately disabled LFO must fail the waveform check.
verilator --binary --timing -Wno-fatal --top-module opna_jt08_tb \
    -DNOLFO -DNEGATIVE_LFO --Mdir "$out/negative" -j 1 \
    "${rtl[@]}" rtl/opna_jt08.sv tests/opna_jt08_tb.sv > "$out/negative-compile.log" 2>&1 || \
    { cat "$out/negative-compile.log"; exit 1; }
if "$out/negative/Vopna_jt08_tb" > "$out/negative.log" 2>&1; then
    echo 'FAIL: disabled LFO unexpectedly passed' >&2; exit 1
fi
grep -q 'LFO has no waveform effect' "$out/negative.log"
echo 'PASS: disabled LFO negative control rejected'
