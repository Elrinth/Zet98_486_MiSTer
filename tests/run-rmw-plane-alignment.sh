#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ghdl -a --std=08 -fsynopsys --workdir="$out" Zet98/sdramc.vhd tests/sdram_request_tb.vhd
ghdl -e --std=08 -fsynopsys --workdir="$out" sdram_request_tb
for drawing in false true; do
    for mhz in 20 60 100; do
        ghdl -r --std=08 -fsynopsys --workdir="$out" sdram_request_tb \
            -gBUFFERED=true -gUSE_SUB="$drawing" -gCPU_MHZ="$mhz" -gMEM_PHASE_PS=4700 --assert-level=error
    done
done
# Reinstate each original unaligned RMW4 write column independently. The
# transaction corpus includes all four addressed planes and checks SDRAM pins.
for port in cpu sub; do
    mkdir "$out/$port"
    PORT="$port" OUT="$out/$port/bad.vhd" python3 - <<'PY'
import os
from pathlib import Path
p = os.environ['PORT']
s = Path('Zet98/sdramc.vhd').read_text()
old = f"{p}_address(9 downto 2) & \"00\"; -- {p.upper()}_RMW4_ALIGN"
assert s.count(old) == 1
Path(os.environ['OUT']).write_text(s.replace(old, f'{p}_address(9 downto 0);'))
PY
    ghdl -a --std=08 -fsynopsys --workdir="$out/$port" "$out/$port/bad.vhd" tests/sdram_request_tb.vhd
    ghdl -e --std=08 -fsynopsys --workdir="$out/$port" sdram_request_tb
    drawing=false; if [[ "$port" = sub ]]; then drawing=true; fi
    if ghdl -r --std=08 -fsynopsys --workdir="$out/$port" sdram_request_tb \
        -gBUFFERED=true -gUSE_SUB="$drawing" -gCPU_MHZ=60 --assert-level=error > "$out/bad.log" 2>&1; then
        echo "FAIL: unaligned $port RMW4 column accepted"; exit 1
    fi
    grep -q 'SDRAM column/bank mismatch' "$out/bad.log" || { cat "$out/bad.log"; exit 1; }
    echo "PASS: unaligned $port RMW4 write column rejected"
done
