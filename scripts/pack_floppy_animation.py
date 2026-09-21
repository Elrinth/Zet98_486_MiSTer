#!/usr/bin/env python3
"""Losslessly pack the canonical 59-frame disk ROM into shared 4x4 tiles."""
import argparse
from pathlib import Path


def pack(source, output_dir):
    pixels = [int(token, 2) for token in source.read_text().split()]
    if len(pixels) != 59 * 50 * 56 or any(p not in range(4) for p in pixels):
        raise ValueError('Expected 59 frames of 50x56 two-bit pixels')
    tiles, numbers, tile_map = [], {}, []
    for frame in range(59):
        for y in range(0, 56, 4):
            for x in range(0, 50, 4):
                tile = tuple(pixels[frame*2800+(y+dy)*50+x+dx] if x+dx < 50 else 0
                             for dy in range(4) for dx in range(4))
                if tile not in numbers:
                    numbers[tile] = len(tiles)
                    tiles.append(tile)
                tile_map.append(numbers[tile])
    if len(tiles) != 495:
        raise ValueError('The RTL expects the supplied animation (495 distinct tiles)')
    # Verify every original pixel, including the partial rightmost tile.
    for frame in range(59):
        for y in range(56):
            for x in range(50):
                tile = tiles[tile_map[frame*182+(y//4)*13+x//4]]
                assert tile[(y%4)*4+x%4] == pixels[frame*2800+y*50+x]
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, values, bits in [('floppy-tile-map.mem', tile_map, 9),
                              ('floppy-tile-pixels.mem', [p for t in tiles for p in t], 2)]:
        tokens = [format(value, f'0{bits}b') for value in values]
        rows = [' '.join(tokens[n:n+32]) for n in range(0, len(tokens), 32)]
        (output_dir/name).write_bytes(('\n'.join(rows)+'\n').encode('ascii'))
    print(f'PASS: {len(pixels)} pixels reconstructed; {len(tiles)} tiles; '
          f'{len(tile_map)*9+len(tiles)*32} ROM bits')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path('rtl/assets/floppy-animation.mem'))
    parser.add_argument('--output-dir', type=Path, default=Path('rtl/assets'))
    args = parser.parse_args()
    pack(args.source, args.output_dir)
