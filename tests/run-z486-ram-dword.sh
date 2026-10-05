#!/usr/bin/env bash
set -euo pipefail
export Z486_PIPELINE_REGS=2 Z486_ICACHE_SET_BITS=9 Z486_DCACHE_SET_BITS=7
export MEMORY_COMPLETION_OUT=${MEMORY_COMPLETION_OUT:-/project/dword-out}
exec bash "$(dirname "$0")/run-z486-memory-completion.sh" dword
