#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Pack the existing self-drawn activity icons and caption glyphs into one M10K.

1024 x 8 bits: bank 0 holds 17 8x8 glyphs; banks 1-3 contain floppy/CD/HDD,
four 16x16 frames each, four 2-bit pixels per byte. No external artwork.
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GLYPHS = ' LOADINGWRTEHC.01'


def generate():
    font = [int(x, 16) for x in (ROOT / 'rtl/assets/boot-font.mem').read_text().split()]
    icons = [int(x, 16) for x in (ROOT / 'rtl/assets/overlay-icons.mem').read_text().split()]
    data = bytearray(1024)
    for index, char in enumerate(GLYPHS):
        data[index*8:index*8+8] = bytes(font[ord(char)*8:ord(char)*8+8])
    for kind in range(3):
        for frame in range(4):
            for row in range(16):
                for group in range(4):
                    base = kind*2048 + frame*512 + row*16 + group*4
                    data[(kind+1)*256+frame*64+row*4+group] = sum(
                        icons[base+p] << (6-2*p) for p in range(4))
    return ''.join(f'{value:02x}\n' for value in data)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    path = ROOT / 'rtl/assets/activity.mem'
    text = generate()
    if args.check:
        assert path.read_text() == text, 'Regenerate activity.mem'
    else:
        path.write_text(text, encoding='ascii')
    print(f'Activity ROM: {len(GLYPHS)} glyphs, 12 icon frames, 8192 bits')
