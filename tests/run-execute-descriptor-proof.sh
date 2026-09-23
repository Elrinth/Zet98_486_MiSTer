#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/prove-execute-descriptor-payload.py
python3 tests/prove-global-descriptor-limits.py
