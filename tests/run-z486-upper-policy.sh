#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tests/run-cache-map.sh
mkdir -p build/z486-upper-policy
ghdl --synth --std=08 --out=verilog -gUPPER_RAM_ICACHE=1 rtl/cpu/pc98_cache_policy.vhd -e pc98_cache_policy > build/z486-upper-policy/policy.v
sha256sum rtl/cpu/pc98_cache_policy.vhd build/z486-upper-policy/policy.v
