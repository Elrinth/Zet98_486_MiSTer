#!/usr/bin/env python3
"""Extract/repack a DOS D88 for file editing with mtools. Never overwrite files.

Repacking preserves every D88 sector header and the original boot sector;
the raw file must retain the original geometry. Only sector payloads change.
"""
import argparse
from pathlib import Path
from d88_file import D88


def repack(disk, raw):
    if len(raw) != len(disk.raw):
        raise ValueError('Raw image size changed')
    if raw[:disk.bps] != disk.raw[:disk.bps]:
        raise ValueError('Boot sector changed; only DOS file editing is supported')
    result = bytearray(disk.data)
    cursor = 0
    for pos, size in disk.sectors:
        result[pos:pos + size] = raw[cursor:cursor + size]
        cursor += size
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    extract = sub.add_parser('extract')
    extract.add_argument('image', type=Path)
    extract.add_argument('output', type=Path)
    pack = sub.add_parser('repack')
    pack.add_argument('image', type=Path)
    pack.add_argument('raw', type=Path)
    pack.add_argument('output', type=Path)
    args = parser.parse_args()
    disk = D88(args.image)
    data = disk.raw if args.command == 'extract' else repack(disk, args.raw.read_bytes())
    with args.output.open('xb') as stream:
        stream.write(data)
