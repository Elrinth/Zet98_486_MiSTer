#!/usr/bin/env bash
set -euo pipefail
if [ "${FLAT_REGRESSION_INNER:-0}" != 1 ]; then
    exec timeout --kill-after=10s 600s env FLAT_REGRESSION_INNER=1 bash "$0"
fi
cd "$(dirname "$0")/.."
test "$PWD" = /project
evidence=/project/flat-regression-evidence
mkdir "$evidence"
cp rtl/vendor/z486/z486.sv "$evidence/z486-original.sv"
python3 tests/make_vipt_flat_candidate.py "$evidence/z486-candidate.sv" --no-monitor
cp "$evidence/z486-candidate.sv" rtl/vendor/z486/z486.sv
trap 'cp "$evidence/z486-original.sv" rtl/vendor/z486/z486.sv' EXIT
for name in z486 z486-gpr-forward z486-unreal-cs; do
    if ! bash "tests/run-$name.sh" > "$evidence/$name.log" 2>&1; then
        tail -n 25 "$evidence/$name.log"
        echo "FAIL $name"
        exit 1
    fi
    tail -n 3 "$evidence/$name.log"
    echo "PASS flat candidate regression $name"
done
echo 'PASS generic CPU/cache/64MB, forwarding, and mode transitions; production untouched'
