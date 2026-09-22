#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Architectural and cache/coherence checks after CPU datapath changes.
bash tests/run-cpu.sh
LOWMEM_CACHE=1 CPU_REP_COUNTS=1 bash tests/run-cpu.sh
bash tests/run-extmem.sh
bash tests/run-cache.sh
bash tests/run-upper-cache.sh
