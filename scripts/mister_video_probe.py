#!/usr/bin/env python
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read MiSTer scaler metadata only; never write registers or frame memory.

Uses the 16-byte header described by Main_MiSTer/scaler.cpp and scaler.h.
Run on MiSTer as root. Reports the source raster and actual scaled viewport,
not the physical panel resolution or a measurement of game frame rate.
"""
from __future__ import print_function
import json
import mmap
import os
import struct


def main():
    fd = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
    try:
        region = mmap.mmap(fd, 16, flags=mmap.MAP_SHARED,
                           prot=mmap.PROT_READ, offset=0x20000000)
        try:
            header = region[:16]
        finally:
            region.close()
    finally:
        os.close(fd)
    if header[:2] != b'\x01\x01':
        raise SystemExit('Unsupported or unavailable MiSTer scaler header')
    size, width, height, stride, out_width, out_height = struct.unpack(
        '>H2x5H', header[2:16])
    if not (16 <= size <= 4096 and 0 < width <= 2048 and
            0 < height <= 2048 and width*3 <= stride <= 8192):
        raise SystemExit('Implausible scaler metadata; no frame read attempted')
    print(json.dumps(dict(source_width=width, source_height=height,
                          stride=stride, header_bytes=size,
                          viewport_width=out_width, viewport_height=out_height),
                     sort_keys=True))


if __name__ == '__main__':
    main()
