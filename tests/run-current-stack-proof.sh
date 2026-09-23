#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/prove-current-stack-pop.py
python3 tests/prove-stack-pop-predecode.py
