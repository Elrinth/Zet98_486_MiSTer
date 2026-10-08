#!/usr/bin/env bash
# Run the retained z486 regressions and report every result (no early stop).
cd "$(dirname "$0")/.."
fail=0
for t in gpr-forward rmw-reload "" pm-payload pit-pm pit-ldt lss-stack stack-allocation unreal-cs \
         prefetch memory-init ide-copy-regression pm16-limit load-limits; do
    s=tests/run-z486${t:+-$t}.sh
    if bash "$s" > "/tmp/$(basename "$s").log" 2>&1; then echo "SUITE PASS $s"; else echo "SUITE FAIL $s"; tail -n 25 "/tmp/$(basename "$s").log"; fail=1; fi
done
exit $fail
