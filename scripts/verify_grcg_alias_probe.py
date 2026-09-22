#!/usr/bin/env python3
"""Verify RMW writes through B/R/G/E aliases, including neighbouring bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

TILES = (0x3c, 0xa5, 0x5a, 0xc3)
WRITES = (((2, 0x5a), (3, 0xa5)), ((2, 0x5a),), ((3, 0xa5),),
          ((3, 0xc3), (4, 0x3c)))
RECORDS = 2*16*4*4


def records():
    for page in range(2):
        for disabled in range(16):
            for alias in range(4):
                for access, writes in enumerate(WRITES):
                    pixels = bytearray((offset*73 + plane*61 + page*29 + 3) % 256
                                       for plane in range(4) for offset in range(8))
                    for plane, tile in enumerate(TILES):
                        if disabled & (1 << plane):
                            continue
                        for offset, mask in writes:
                            index = plane*8+offset
                            pixels[index] = sum(((tile if mask & (1 << bit)
                                                  else pixels[index]) >> bit & 1) << bit
                                                for bit in range(8))
                    yield bytes((page, disabled, alias, access)), bytes(pixels)


def inspect(data):
    if len(data) != 16+36*RECORDS or data[:8] != b'Z98GAL1\0':
        raise ValueError('Wrong plane-alias capture header or length')
    if data[8:16] != struct.pack('<H', RECORDS)+bytes(6):
        raise ValueError('Wrong record count or reserved bytes')
    mismatches = 0
    bad_records = 0
    by_alias = [0]*4
    first = []
    for number, (header, expected) in enumerate(records()):
        at = 16+36*number
        if data[at:at+4] != header:
            raise ValueError(f'Wrong record order at {number}')
        actual = data[at+4:at+36]
        wrong = [(i, a, b) for i, (a, b) in enumerate(zip(actual, expected)) if a != b]
        mismatches += len(wrong)
        if wrong:
            bad_records += 1
            by_alias[header[2]] += 1
        for index, actual_byte, expected_byte in wrong:
            if len(first) < 12:
                first.append(dict(page=header[0], disabled=header[1], alias=header[2],
                                  access=header[3], plane=index//8,
                                  offset=f'{0x7f00+index%8:04x}',
                                  actual=actual_byte, expected=expected_byte))
    return dict(capture_sha256=hashlib.sha256(data).hexdigest(), records=RECORDS,
                compared_bytes=RECORDS*32, mismatching_records=bad_records,
                mismatching_bytes=mismatches, mismatching_records_by_alias=by_alias,
                first_mismatches=first)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    result = inspect(parser.parse_args().capture.read_bytes())
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result['mismatching_bytes']))
