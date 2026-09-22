#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tests/run-decode-buffer.sh
bash tests/run-cpu.sh
LOWMEM_CACHE=1 CPU_REP_COUNTS=1 bash tests/run-cpu.sh
