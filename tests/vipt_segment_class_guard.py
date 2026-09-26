"""Local-only exploration of a conservative direct-load admission predicate.

The candidate permits the common 64 KiB and 4 GiB descriptor limits and
falls back to the existing microcode path for every other limit. It is not a
production CPU change or a replacement for actual CPU/timing qualification.
"""

from random import Random


def reference(offset: int, limit: int, size_code: int) -> bool:
    extra = (0, 1, 3)[size_code]
    return offset + extra <= limit and offset + extra <= 0xFFFFFFFF


def class_guard(offset: int, limit: int, size_code: int) -> bool:
    extra = (0, 1, 3)[size_code]
    if limit == 0xFFFF:
        return offset >> 16 == 0 and (offset & 0xFFFF) <= 0xFFFF - extra
    if limit == 0xFFFFFFFF:
        return offset <= 0xFFFFFFFF - extra
    return False


cases = 0
admitted = 0
for limit in (0xFFFF, 0xFFFFFFFF):
    if limit == 0xFFFF:
        offsets = range(0x10000)
    else:
        offsets = (*range(1024), *range(0xFFFFFC00, 0x100000000))
    for offset in offsets:
        for size_code in range(3):
            assert class_guard(offset, limit, size_code) == reference(offset, limit, size_code)
            cases += 1
            admitted += class_guard(offset, limit, size_code)

rng = Random(0x9821)
for _ in range(100000):
    offset = rng.getrandbits(32)
    limit = rng.getrandbits(32)
    size_code = rng.randrange(3)
    assert not class_guard(offset, limit, size_code) or reference(offset, limit, size_code)
    cases += 1

for limit in (0, 1, 0xFFFE, 0x10000, 0xFFFFFFFE):
    for offset in (0, 1, 0xFFFC, 0xFFFD, 0xFFFE, 0xFFFF, 0x10000, 0xFFFFFFFC, 0xFFFFFFFF):
        for size_code in range(3):
            assert not class_guard(offset, limit, size_code)
            cases += 1

print(f"PASS conservative class guard: {cases} cases, {admitted} accepted in exhaustive/boundary classes")
