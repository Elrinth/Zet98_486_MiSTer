#!/usr/bin/env python3
"""Check spatial samples from four full-plane VRAM transfer operations."""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def seed(page, plane):
    low = (3 + page * 37 + plane * 61) & 255
    return low | ((low ^ 255) << 8)


def pattern_byte(page, plane, offset):
    word = (((offset // 2) * 73 + seed(page, plane)) & 65535)
    word ^= ((offset // 2) << 3) & 65535
    return (word >> (8 * (offset & 1))) & 255


def verify(data):
    assert data[:8] == b'Z98BLK1\0', 'Unexpected signature'
    assert struct.unpack_from('<4H', data, 8) == (32, 4096, 32768, 0)
    assert len(data) == 16 + 32 * 4104, 'Incomplete or extra records'
    failures = []
    mismatch_count = 0
    pos = 16
    for operation in range(4):
        for page in range(2):
            for plane in range(4):
                assert data[pos:pos+8] == bytes([operation, page, plane, 0, 0, 0, 0, 0])
                actual = data[pos+8:pos+4104]
                pos += 4104
                index = 0
                for sample in range(64):
                    offset = sample * 512 + ((sample * 7) & 127)
                    if sample == 63:
                        offset = 0x7fc0
                    for address in range(offset, offset + 64):
                        if operation < 2:
                            expected = pattern_byte(page, plane, address)
                        else:
                            old = (seed(page, plane) >> (8 * (address & 1))) & 255
                            mask = (pattern_byte(page, 0, address) if operation == 2
                                    else (0x5a if address & 1 == 0 else 0xa5))
                            tile = [0x3c, 0xa5, 0x5a, 0xc3][plane]
                            expected = (old & (mask ^ 255)) | (tile & mask)
                        if actual[index] != expected:
                            mismatch_count += 1
                            if len(failures) < 16:
                                failures.append(dict(operation=operation, page=page, plane=plane,
                                                     address=address, expected=expected,
                                                     actual=actual[index]))
                        index += 1
    return dict(passed=mismatch_count == 0, records=32, compared_bytes=131072,
                bytes_per_plane_written=32768, mismatches=mismatch_count,
                first_mismatches=failures, sha256=hashlib.sha256(data).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    args = parser.parse_args()
    result = verify(args.capture.read_bytes())
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['passed'] else 1)
