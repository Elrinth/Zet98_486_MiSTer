#!/usr/bin/env bash
set -euo pipefail
if [ "${SEGMENT_REGRESSION_INNER:-0}" != 1 ]; then
 exec timeout --kill-after=10s 600s env SEGMENT_REGRESSION_INNER=1 bash "$0"
fi
cd "$(dirname "$0")/.."
# This script is run exclusively in the disposable copied simulation snapshot.
# Save both exact sources; never apply this script to the developer checkout.
test "$PWD" = /project
evidence=/project/segment-regression-evidence
mkdir "$evidence"
cp rtl/vendor/z486/z486.sv "$evidence/z486-original.sv"
python3 tests/make_vipt_segment_candidate.py "$evidence/z486-candidate.sv" --no-monitor
cp "$evidence/z486-candidate.sv" rtl/vendor/z486/z486.sv
trap 'cp "$evidence/z486-original.sv" rtl/vendor/z486/z486.sv' EXIT
for name in z486 z486-gpr-forward z486-unreal-cs z486-pm-payload; do
 if ! bash "tests/run-$name.sh" > "$evidence/$name.log" 2>&1; then
  tail -n 35 "$evidence/$name.log"; echo "FAIL $name"; exit 1
 fi
 tail -n 4 "$evidence/$name.log"
 echo "PASS segment candidate regression $name"
done
echo 'PASS: candidate general CPU/cache/64MB, forwarding, mode transitions, protected payload regressions; production source untouched'
