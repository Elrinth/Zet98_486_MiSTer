#!/usr/bin/env bash
# Exercise the changed segment admission in the shipped PR2 / IC32 / DC8 profile.
set -euo pipefail
cd "$(dirname "$0")/.."
real_verilator=$(command -v verilator)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
cat > "$out/verilator" <<EOF
#!/bin/sh
exec "$real_verilator" -DZET98_Z486_PIPELINE_REGS=2 -DZET98_Z486_ICACHE_SET_BITS=9 "\$@"
EOF
chmod +x "$out/verilator"
export PATH="$out:$PATH"
bash tests/run-z486-pm16-limit.sh
bash tests/run-z486-load-limits.sh
bash tests/run-z486.sh
echo 'PASS: production PR2 / IC32 / DC8 segment limits, CPU, cache and 64 MiB RAM'
