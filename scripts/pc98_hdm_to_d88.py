#!/usr/bin/env python3
"""Convert a raw PC-98 2HD floppy image (.hdm/.tfd, 77 cylinders x 2 heads x
8 sectors x 1024 bytes = 1,261,568 bytes) to D88.

Usage: pc98_hdm_to_d88.py INPUT.hdm OUTPUT.d88 [DISK-NAME]
"""
import struct, sys

CYL, HEADS, SECS, SSIZE, N = 77, 2, 8, 1024, 3

def convert(raw, name=b''):
    if len(raw) != CYL * HEADS * SECS * SSIZE:
        raise SystemExit('expected %d bytes (2HD 1024-byte sectors), got %d'
                         % (CYL * HEADS * SECS * SSIZE, len(raw)))
    tracks = []
    for c in range(CYL):
        for h in range(HEADS):
            t = b''
            for r in range(1, SECS + 1):
                off = ((c * HEADS + h) * SECS + (r - 1)) * SSIZE
                # C, H, R, N, sectors in track, density (00 = MFM), deleted,
                # status, 5 reserved, data size
                t += struct.pack('<BBBBHBBB5xH', c, h, r, N, SECS, 0, 0, 0, SSIZE)
                t += raw[off:off + SSIZE]
            tracks.append(t)
    header_size = 0x2B0
    offsets, pos = [], header_size
    for t in tracks:
        offsets.append(pos)
        pos += len(t)
    offsets += [0] * (164 - len(offsets))
    header = name[:16].ljust(17, b'\0') + b'\0' * 9 + bytes([0, 0x20]) + struct.pack('<I', pos)
    header += struct.pack('<164I', *offsets)
    assert len(header) == header_size
    return header + b''.join(tracks)

if __name__ == '__main__':
    if len(sys.argv) not in (3, 4):
        raise SystemExit(__doc__)
    raw = open(sys.argv[1], 'rb').read()
    name = sys.argv[3].encode('ascii', 'replace') if len(sys.argv) == 4 else b''
    out = convert(raw, name)
    open(sys.argv[2], 'wb').write(out)
    print('%s: %d bytes, 154 tracks' % (sys.argv[2], len(out)))
