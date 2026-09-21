#!/usr/bin/env python3
"""Check a private conventional-RAM diagnostic capture against known bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def inspect(data):
    if len(data) != 16 + 3*3082 or data[:8] != b'Z98BYTE1':
        raise ValueError('Wrong conventional-byte probe header or length')
    segment, allocation_end, bank89, bankab, count = struct.unpack_from('<HHBBH', data, 8)
    if count != 3 or allocation_end < 0x9100 or segment > 0x6000:
        raise ValueError('Invalid probe allocation or record count')
    # Independent arithmetic equivalent of the assembler's fixed pattern.
    pattern = bytes(((offset*73+19) ^ (offset//256)) % 256 for offset in range(1026))
    checks = []
    for record, expected_segment in enumerate((0x7000, 0x8000, 0x9000)):
        at = 16 + record*3082
        actual_segment, = struct.unpack_from('<H', data, at)
        if actual_segment != expected_segment:
            raise ValueError('Wrong probe segment ordering')
        at += 2
        for name, expected in (('byte_reads', pattern[:1024]),
                               ('aligned_words', pattern[:1024]),
                               ('odd_words', pattern[1:1025]),
                               ('partial_writes', struct.pack('<4H', 0xa5c3, 0x3cc3, 0x96e1, 0x69e1))):
            observed = data[at:at+len(expected)]
            bad = [dict(offset=i, actual=a, expected=b)
                   for i, (a, b) in enumerate(zip(observed, expected)) if a != b]
            checks.append(dict(segment=f'{actual_segment:04x}', check=name,
                               bytes=len(expected), mismatches=len(bad), first_mismatches=bad[:8]))
            at += len(expected)
    return dict(capture_sha256=hashlib.sha256(data).hexdigest(),
                program_segment=f'{segment:04x}', allocation_end=f'{allocation_end:04x}',
                bank89=f'{bank89:02x}', bankab=f'{bankab:02x}',
                mismatches=sum(check['mismatches'] for check in checks), checks=checks)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    result = inspect(parser.parse_args().capture.read_bytes())
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result['mismatches']))
