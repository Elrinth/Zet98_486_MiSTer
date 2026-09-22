#!/usr/bin/env python3
"""Check synthetic pixel expansion and carry-chain captures independently."""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def expected_pixels():
    # String concatenation deliberately avoids the assembly's bitwise LUT
    # construction. Each source pixel becomes two adjacent output pixels.
    doubled = [int(''.join(c*2 for c in f'{value:08b}'), 2) for value in range(256)]
    expanded, shifted = bytearray(), bytearray()
    for value in range(256):
        pixels = (doubled[value] << 16) | doubled[value ^ 0xa5]
        expanded.extend(pixels.to_bytes(4, 'big'))
        shifted.extend(((pixels*2) % (1 << 32)).to_bytes(4, 'big'))
    return bytes(expanded), bytes(shifted)


def inspect(data):
    if len(data) != 4116 or data[:8] != b'Z98GLYF1':
        raise ValueError('Wrong glyph arithmetic header or length')
    segment, allocation_end, bank89, bankab, count = struct.unpack_from('<HHBBH', data, 8)
    if count != 2 or segment > 0x6000 or allocation_end < 0x9300:
        raise ValueError('Invalid allocation or record count')
    expected = expected_pixels()
    checks = []
    for record, expected_segment in enumerate((0x7000, 0x9000)):
        at = 16 + record*2050
        actual_segment, = struct.unpack_from('<H', data, at)
        if actual_segment != expected_segment:
            raise ValueError('Wrong glyph record order')
        at += 2
        for name, pixels in zip(('odd_lookup_expansion', 'carry_chain_shift'), expected):
            observed = data[at:at+1024]
            bad = [dict(offset=i, actual=a, expected=b)
                   for i, (a, b) in enumerate(zip(observed, pixels)) if a != b]
            checks.append(dict(segment=f'{actual_segment:04x}', check=name, bytes=1024,
                               mismatches=len(bad), first_mismatches=bad[:8]))
            at += 1024
    return dict(capture_sha256=hashlib.sha256(data).hexdigest(),
                program_segment=f'{segment:04x}', allocation_end=f'{allocation_end:04x}',
                bank89=f'{bank89:02x}', bankab=f'{bankab:02x}',
                mismatches=sum(c['mismatches'] for c in checks), checks=checks)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    result = inspect(parser.parse_args().capture.read_bytes())
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result['mismatches']))
