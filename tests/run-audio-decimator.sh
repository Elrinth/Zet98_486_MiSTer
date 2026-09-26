#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
iverilog -g2012 -s audio_decimator_tb -o "$out/sim" rtl/audio_decimator.sv tests/audio_decimator_tb.sv
vvp "$out/sim" +out="$out/good.txt" > /dev/null
python3 tests/audio_decimator_check.py "$out/good.txt"
# A plain 24 kHz-null average (FIR reduced to a boxcar) must fail the alias bound.
python3 - "$out/box.mem" <<'EOF'
import sys
open(sys.argv[1], 'w').write(''.join('%05x\n' % (v & 0x3ffff) for v in [65536] * 32 + [0] * 224))
EOF
sed "s#rtl/assets/audio-decimator-coeffs.mem#$out/box.mem#" tests/audio_decimator_tb.sv > "$out/box_tb.sv"
iverilog -g2012 -s audio_decimator_tb -o "$out/box" rtl/audio_decimator.sv "$out/box_tb.sv"
vvp "$out/box" +out="$out/box.txt" > /dev/null
if python3 tests/audio_decimator_check.py "$out/box.txt" > "$out/box.log"; then
    cat "$out/box.log"; echo "FAIL: boxcar decimator accepted"; exit 1
fi
echo "PASS: boxcar decimator rejected"
