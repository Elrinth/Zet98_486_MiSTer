#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=build/grcg-alias-diagnostic
mkdir -p "$out"
nasm -f bin tests/hardware/grcg_alias_probe.asm -o "$out/grcg-alias-probe.com"
nasm -DPROBE_SHELL=1 -f bin tests/hardware/grcg_alias_probe.asm -o "$out/grcg-alias-shell.com"
sha256sum "$out"/*.com
python3 tests/test_grcg_alias_probe.py
echo 'PASS: GRCG plane-alias DOS probes assemble; execution/capture verification is separate'
