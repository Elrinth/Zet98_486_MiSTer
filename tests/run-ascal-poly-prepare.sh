#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/prove-ascal-poly-bound.py --prepare build/ascal-poly-proof
