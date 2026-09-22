#!/usr/bin/env python3
"""Check a combined hardware font/render capture against the owner's font."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

CODES = (0x2009, 0x5309, 0x7409, 0x6109, 0x7209, 0x4309, 0x6f09,
         0x6e09, 0x6909, 0x7509, 0x6509, 0x4f09, 0x7009, 0x7309)


def expected_stages(code, rom):
    column, row = code >> 8, code & 255
    start = 0x40000 + 0x1800 + (row-1)*96*32 + (column-32)*32
    raw = bytes(rom[start + half*16 + line] for line in range(16) for half in range(2))
    # Pixels, not the CPU's odd-address word table or carry chain.
    expanded = b''.join(int(''.join(pixel*2 for pixel in f'{byte:08b}'), 2).to_bytes(2, 'big')
                        for byte in raw)
    shifted = b''.join(((int.from_bytes(expanded[i:i+4], 'big') << 1) & 0xffffffff).to_bytes(4, 'big')
                       for i in range(0, 64, 4))
    planes = []
    for plane in range(4):
        pixels = bytearray([3 + plane*61] * (33*6))
        for line in range(16):
            for duplicate in range(2):
                for byte in range(4):
                    # Clear the shadow first, then set foreground pixels.
                    pixels[(line*2+duplicate+1)*6 + 1+byte] &= ~expanded[line*4+byte]
        for line in range(16):
            for duplicate in range(2):
                for byte in range(4):
                    pixels[(line*2+duplicate)*6 + 1+byte] |= shifted[line*4+byte]
        planes.append(bytes(pixels))
    return [('font', raw), ('expanded', expanded), ('shifted', shifted)] + [
        (f'plane{plane}', pixels) for plane, pixels in enumerate(planes)]


def inspect(data, rom):
    if len(rom) != 550912:
        raise ValueError('Expected the exact 550912-byte combined boot ROM')
    if len(data) != 16+56*958 or data[:8] != b'Z98PIPE1':
        raise ValueError('Wrong pipeline capture header or length')
    cs, allocation, count, record_bytes = struct.unpack_from('<4H', data, 8)
    if cs > 0x5000 or allocation < 0xa000 or count != 56 or record_bytes != 958:
        raise ValueError('Invalid allocation or record dimensions')
    at, checks = 16, []
    for segment in (0x7000, 0x8bde):
        for interrupts in (0, 1):
            for code in CODES:
                metadata = struct.pack('<HHBB', segment, code, interrupts, 0)
                if data[at:at+6] != metadata:
                    raise ValueError(f'Wrong pipeline record order at offset {at}')
                at += 6
                for stage, expected in expected_stages(code, rom):
                    actual = data[at:at+len(expected)]
                    bad = [dict(offset=i, actual=a, expected=e)
                           for i, (a, e) in enumerate(zip(actual, expected)) if a != e]
                    checks.append(dict(segment=f'{segment:04x}', code=f'{code:04x}',
                                       interrupts=bool(interrupts), stage=stage,
                                       bytes=len(expected), mismatches=len(bad),
                                       first_mismatches=bad[:6]))
                    at += len(expected)
    assert at == len(data)
    return dict(capture_sha256=hashlib.sha256(data).hexdigest(),
                boot_sha256=hashlib.sha256(rom).hexdigest(), program_segment=f'{cs:04x}',
                allocation_end=f'{allocation:04x}', records=count,
                bytes_checked=sum(c['bytes'] for c in checks),
                mismatches=sum(c['mismatches'] for c in checks), checks=checks)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('boot_rom', type=Path)
    args = parser.parse_args()
    result = inspect(args.capture.read_bytes(), args.boot_rom.read_bytes())
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result['mismatches']))
