#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
mapfile -t rtl < <(find rtl/vendor/jt08/jt12/hdl rtl/vendor/jt08/jt49/hdl -name '*.v' ! -name jt12_mmr.v -print | sort)
for bug in busy strobe; do
    python3 - "$bug" "$out/mmr.v" <<'PY'
import pathlib,sys
s=pathlib.Path('rtl/vendor/jt08/jt12/hdl/jt12_mmr.v').read_text()
if sys.argv[1]=='busy':
    s=s.replace('write && addr[0] && !psg_nowait_write', 'write && addr[0]')
else:
    s=s.replace("if (use_chipid && use_ssg) psg_wr_n <= 1'b1;", '')
pathlib.Path(sys.argv[2]).write_text(s)
PY
    verilator --binary --timing -Wno-fatal --top-module opna_jt08_tb \
      -DPSG_ONLY --Mdir "$out/obj-$bug" -j 2 \
      "${rtl[@]}" "$out/mmr.v" rtl/opna_jt08.sv tests/opna_jt08_tb.sv \
      > "$out/compile-$bug.log" 2>&1 || { tail -n 60 "$out/compile-$bug.log"; exit 1; }
    if "$out/obj-$bug/Vopna_jt08_tb" > "$out/run-$bug.log" 2>&1; then
        echo "FAIL: old PSG $bug behavior accepted"; exit 1
    fi
    if [ "$bug" = busy ]; then
        grep -q 'PSG sample write incorrectly asserts busy' "$out/run-$bug.log"
    else
        grep -q 'Fast PSG address change corrupted register' "$out/run-$bug.log"
    fi
    echo "PASS: old PSG $bug behavior rejected"
done
