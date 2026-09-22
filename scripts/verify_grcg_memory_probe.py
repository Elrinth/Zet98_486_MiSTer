#!/usr/bin/env python3
"""Check synthetic GRCG captures against independent per-pixel operations."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

TILES = (0x3c, 0xa5, 0x5a, 0xc3)


def expected_records():
    records = []
    for source in range(2):
        pages = []
        for page in range(2):
            planes = [bytearray((offset*17 + plane*61 + page*29 + source*7 + 3) % 256
                                for offset in range(256)) for plane in range(4)]

            def snapshot(phase):
                records.append((bytes((source, page, phase, 0)), b''.join(planes)))

            def masked(positions, source_offsets):
                for offset, mask_index in zip(positions, source_offsets):
                    mask = (mask_index*73 + 19) % 256
                    for plane, pixels in enumerate(planes):
                        # Each set mask pixel selects the tile pixel; otherwise
                        # the old destination pixel survives. No HDL RMW formula.
                        pixels[offset] = sum(((TILES[plane] if mask & (1 << bit)
                                               else pixels[offset]) >> bit & 1) << bit
                                             for bit in range(8))

            snapshot(0)
            masked(range(0x10, 0x50), range(64))
            snapshot(1)
            masked(range(0x51, 0x71), range(64, 96))
            snapshot(2)
            masked(range(0x80, 0xa0), range(96, 128))
            snapshot(3)
            masked(range(0xb1, 0xd1, 2), range(128, 144))
            snapshot(4)
            # TDW command 85h enables only planes 1 and 3. CPU bytes are ignored.
            for plane, tile in ((1, 0x0f), (3, 0x96)):
                planes[plane][0xd1:0xe1] = bytes([tile])*16
            snapshot(5)
            for row in range(2):
                for duplicate in range(2):
                    start = (row*2+duplicate)*80
                    masked(range(start, start+4), range(160+row*4, 164+row*4))
            snapshot(6)
            pages.append(b''.join(planes))
        for page, pixels in enumerate(pages):
            records.append((bytes((source, page, 7, 0)), pixels))
    return records


def inspect(data):
    if len(data) != 32912 or data[:8] != b'Z98GRCG1':
        raise ValueError('Wrong GRCG capture header or length')
    segment, allocation, bank89, bankab, count = struct.unpack_from('<HHBBH', data, 8)
    if count != 32 or segment > 0x6000 or allocation < 0x9100:
        raise ValueError('Invalid GRCG capture allocation or record count')
    checks = []
    for number, (header, pixels) in enumerate(expected_records()):
        at = 16 + number*1028
        if data[at:at+4] != header:
            raise ValueError(f'Wrong source/page/phase order in record {number}')
        at += 4
        for plane in range(4):
            observed = data[at+plane*256:at+(plane+1)*256]
            expected = pixels[plane*256:(plane+1)*256]
            bad = [dict(vram_offset=f'{0x100+i:04x}', actual=a, expected=b)
                   for i, (a, b) in enumerate(zip(observed, expected)) if a != b]
            checks.append(dict(source='upper' if header[0] else 'low', page=header[1],
                               phase=header[2], plane=plane, bytes=256,
                               mismatches=len(bad), first_mismatches=bad[:6]))
    return dict(capture_sha256=hashlib.sha256(data).hexdigest(),
                program_segment=f'{segment:04x}', allocation_end=f'{allocation:04x}',
                bank89=f'{bank89:02x}', bankab=f'{bankab:02x}', records=count,
                bytes_checked=sum(c['bytes'] for c in checks),
                mismatches=sum(c['mismatches'] for c in checks), checks=checks)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    result = inspect(parser.parse_args().capture.read_bytes())
    print(json.dumps(result, indent=2))
    raise SystemExit(bool(result['mismatches']))
