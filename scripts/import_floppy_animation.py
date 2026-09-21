#!/usr/bin/env python3
"""Compile the user-supplied rotating-disk GIF into a small FPGA pixel ROM.

Only the disk rectangle is retained; the original caption is never imported.
Four nearest RGB colors preserve the pixel-art appearance while limiting the
59-frame ROM to 330400 data bits. Requires Pillow; no network access is used.
"""
import argparse
import hashlib
from pathlib import Path
from PIL import Image, ImageSequence
from pack_floppy_animation import pack

PALETTE = [(0, 0, 0), (0, 68, 255), (255, 238, 255), (119, 119, 119)]
BOX = (136, 94, 186, 150)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('gif', type=Path)
    parser.add_argument('--output', type=Path, default=Path('rtl/assets/floppy-animation.mem'))
    args = parser.parse_args()
    source = Image.open(args.gif)
    if source.size != (320, 240) or source.n_frames != 59:
        raise ValueError('Expected the supplied 320x240, 59-frame disk animation')
    indices = []
    color_map = {}
    for frame in ImageSequence.Iterator(source):
        for color in frame.convert('RGB').crop(BOX).getdata():
            if color not in color_map:
                color_map[color] = min(range(4), key=lambda n: sum(
                    (color[c] - PALETTE[n][c]) ** 2 for c in range(3)))
            indices.append(color_map[color])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    tokens = [format(i, '02b') for i in indices]
    rows = [' '.join(tokens[n:n+32]) for n in range(0, len(tokens), 32)]
    args.output.write_bytes(('\n'.join(rows) + '\n').encode())
    pack(args.output, args.output.parent)
    print(f'{len(indices)} pixels / {len(indices)*2} bits; source SHA256 '
          f'{hashlib.sha256(args.gif.read_bytes()).hexdigest()}')


if __name__ == '__main__':
    main()
