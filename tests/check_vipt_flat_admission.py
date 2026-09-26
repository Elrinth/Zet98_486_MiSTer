"""Check that the conservative flat-segment candidate never over-admits."""

import random


def reference(offset, limit, size):
    extra = 3 if size & 2 else size
    return offset + extra <= limit


def flat_candidate(offset, raw_limit, granularity, size):
    flat = granularity and raw_limit == 0xFFFFF
    no_wrap = (size == 0 or
               (size == 1 and offset != 0xFFFFFFFF) or
               (size & 2 and offset <= 0xFFFFFFFC))
    return flat and no_wrap


edge_offsets = [0, 1, 0xFFFF, 0x10000, 0xFFFFFFFB,
                0xFFFFFFFC, 0xFFFFFFFD, 0xFFFFFFFE, 0xFFFFFFFF]
edge_limits = [0, 0xFFFF, 0xFFFFE, 0xFFFFF]
rng = random.Random(0x98_162)
cases = [(o, l, g, s) for o in edge_offsets for l in edge_limits
         for g in (0, 1) for s in range(4)]
cases.extend((rng.getrandbits(32), rng.getrandbits(20), rng.randrange(2),
              rng.randrange(4)) for _ in range(100_000))
admitted = 0
for offset, raw_limit, granularity, size in cases:
    limit = (raw_limit << 12 | 0xFFF) if granularity else raw_limit
    candidate = flat_candidate(offset, raw_limit, granularity, size)
    if candidate:
        admitted += 1
        assert reference(offset, limit, size), (offset, raw_limit, granularity, size)
    if granularity and raw_limit == 0xFFFFF:
        assert candidate == reference(offset, limit, size)
assert admitted > 0
print(f"PASS {len(cases)} cases; {admitted} admitted; no over-admission")
