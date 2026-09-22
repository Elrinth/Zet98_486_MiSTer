#!/usr/bin/env python3
"""Verify DOS GRCG comparison captures using per-pixel color equality."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

TILES = (0x3c, 0xa5, 0x5a, 0xc3)
RECORDS = 2*16*4*16


def pixel_byte(page, disabled, offset):
    value = 0
    for bit in range(8):
        match = True
        for plane in range(4):
            if not disabled & (1 << plane):
                actual = (offset*73 + plane*61 + page*29 + 3) % 256
                if (actual >> bit & 1) != (TILES[plane] >> bit & 1):
                    match = False
        if match:
            value |= 1 << bit
    return value


def records():
    for page in range(2):
        for disabled in range(16):
            for alias in range(4):
                for word in range(16):
                    lo, hi, next_byte = (pixel_byte(page, disabled, word*2+n) for n in range(3))
                    yield bytes((page, disabled, alias, word)), struct.pack(
                        '<HHBB', lo | hi << 8, hi | next_byte << 8, lo, hi)


def inspect(data):
    if len(data) != 16+10*RECORDS or data[:8] != b'Z98GCMP1':
        raise ValueError('Wrong GRCG comparison capture header or length')
    if data[8:16] != struct.pack('<H', RECORDS)+bytes(6):
        raise ValueError('Wrong GRCG comparison record count/reserved bytes')
    mismatches = 0
    first = []
    for number, (header, expected) in enumerate(records()):
        at = 16+number*10
        if data[at:at+4] != header:
            raise ValueError(f'Wrong record order at {number}')
        actual = data[at+4:at+10]
        if actual != expected:
            mismatches += 1
            if len(first) < 12:
                first.append(dict(page=header[0], disabled=header[1], alias=header[2],
                                  word=header[3], actual=actual.hex(), expected=expected.hex()))
    return dict(capture_sha256=hashlib.sha256(data).hexdigest(), records=RECORDS,
                compared_bytes=RECORDS*6, mismatching_records=mismatches,
                first_mismatches=first)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    result = inspect(parser.parse_args().capture.read_bytes())
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result['mismatching_records']))
