#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec timeout --signal=TERM --kill-after=10s 600s bash tests/run-z486-ide-bios.sh
