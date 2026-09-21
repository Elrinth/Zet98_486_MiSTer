#!/usr/bin/env python3
"""Compare a private Z98FONT.BIN hardware capture with its boot.rom font."""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def inspect(capture, boot_rom):
    if len(boot_rom) != 550912:
        raise ValueError('Expected a combined 550912-byte Zet98 boot.rom')
    if len(capture) < 10 or capture[:8] != b'Z98FONT2':
        raise ValueError('Wrong font-probe header')
    count, = struct.unpack_from('<H', capture, 8)
    if not count or len(capture) != 10 + count * 66:
        raise ValueError('Truncated or oversized font-probe records')
    mismatches, unstable, samples = [], [], 0
    for record in range(count):
        at = 10 + record * 66
        code, = struct.unpack_from('<H', capture, at)
        high, low = code >> 8, code & 255
        if high and not (32 <= high < 128 and 1 <= low <= 92):
            raise ValueError(f'Unsupported character code {code:04x}')
        for position in range(32):
            half, row = divmod(position, 16)
            offset = (0x800 + low * 16 + row if high == 0 else
                      0x1800 + (low - 1) * 96 * 32 + (high - 32) * 32 + half * 16 + row)
            expected = boot_rom[0x40000 + offset]
            first, delayed = capture[at + 2 + position * 2:at + 4 + position * 2]
            sample = dict(code=f'{code:04x}', half=half, row=row,
                          first=first, delayed=delayed, expected=expected)
            if first != delayed:
                unstable.append(sample)
            if first != expected or delayed != expected:
                mismatches.append(sample)
            samples += 1
    return dict(records=count, samples=samples, mismatches=len(mismatches),
                unstable_reads=len(unstable), first_mismatches=mismatches[:12],
                first_unstable=unstable[:12],
                boot_sha256=hashlib.sha256(boot_rom).hexdigest(),
                capture_sha256=hashlib.sha256(capture).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('boot_rom', type=Path)
    args = parser.parse_args()
    result = inspect(args.capture.read_bytes(), args.boot_rom.read_bytes())
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result['mismatches'] or result['unstable_reads']))
