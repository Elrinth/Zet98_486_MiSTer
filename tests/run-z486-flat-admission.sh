#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SEGMENT_CASE_GENERATOR=tests/make_vipt_flat_cases.py \
SEGMENT_CANDIDATE_GENERATOR=tests/make_vipt_flat_candidate.py \
SEGMENT_EVIDENCE=/project/flat-admission-evidence \
bash tests/run-z486-segment-admission.sh
