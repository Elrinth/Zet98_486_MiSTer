#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Pack user-supplied NP2-style NEC ROMs for the PC98 MiSTer loader.

This converts the file layout only; it does not establish BIOS compatibility.
No ROM data is included. Required: bios.rom (96 KiB), itf.rom (32 KiB),
font.rom (288768 bytes). Optional: sound.rom (16 KiB).
"""
import argparse
import hashlib
from pathlib import Path
import zipfile

SIZES = {'bios.rom': 0x18000, 'itf.rom': 0x8000,
         'font.rom': 288768, 'sound.rom': 0x4000}
OFFSETS = {'bios.rom': 0, 'itf.rom': 0x18000,
           'sound.rom': 0x20000, 'font.rom': 0x40000}


def pack(source):
    source = Path(source)
    parts = {}

    def add(name, data):
        key = name.replace('\\', '/').rsplit('/', 1)[-1].lower()
        if key not in SIZES:
            return
        if key in parts:
            raise ValueError('Ambiguous archive/directory: duplicate ' + key)
        if len(data) != SIZES[key]:
            raise ValueError('%s: expected %d bytes, got %d' % (key, SIZES[key], len(data)))
        parts[key] = data

    if source.is_dir():
        for p in source.iterdir():
            if p.is_file() and p.name.lower() in SIZES:
                add(p.name, p.read_bytes())
    else:
        with zipfile.ZipFile(source) as z:
            for item in z.infolist():
                key = item.filename.replace('\\', '/').rsplit('/', 1)[-1].lower()
                if not item.is_dir() and key in SIZES:
                    if item.file_size != SIZES[key]:
                        raise ValueError('Unexpected size for ' + key)
                    add(item.filename, z.read(item))
    missing = set(SIZES) - {'sound.rom'} - parts.keys()
    if missing:
        raise ValueError('Missing required ROM(s): ' + ', '.join(sorted(missing)))
    result = bytearray(550912)
    for name, data in parts.items():
        start = OFFSETS[name]
        result[start:start+len(data)] = data
    return bytes(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='ZIP or directory with ROM components')
    parser.add_argument('output', type=Path, help='New output file, normally boot.rom')
    args = parser.parse_args()
    try:
        data = pack(args.source)
        with args.output.open('xb') as f:
            f.write(data)
    except (OSError, ValueError, zipfile.BadZipFile) as e:
        parser.exit(1, str(e) + '\n')
    print('Wrote %s (%d bytes)' % (args.output, len(data)))
    print('SHA256: ' + hashlib.sha256(data).hexdigest())
    print('Layout conversion only: hardware compatibility must be tested.')


if __name__ == '__main__':
    main()
