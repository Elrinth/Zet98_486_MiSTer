#!/usr/bin/env python3
"""Compare public video frames against text/glyph pixels, including spacing."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from generate_boot_prompt import FONT, PAGES

for page, lines in enumerate(PAGES, 1):
    header, size, maximum, frame = (Path(sys.argv[1]) / f'page{page}.ppm').read_bytes().split(b'\n', 3)
    assert (header, size, maximum) == (b'P6', b'640 480', b'255')
    expected = bytearray(bytes((8, 12, 20)) * (640*480))
    for row, line in enumerate(lines):
        for column, char in enumerate(line.center(32)):
            for gy, bits in enumerate(bytes.fromhex(FONT[char])):
                for gx in range(5):
                    if not (bits & (16 >> gx)):
                        continue
                    for dy in range(2):
                        for dx in range(2):
                            x = 64 + column*16 + (gx+1)*2 + dx
                            y = 112 + row*32 + gy*2 + dy
                            offset = (y*640+x)*3
                            expected[offset:offset+3] = bytes((232,232,232))
    assert frame == expected, f'Prompt page {page}: {sum(a!=b for a,b in zip(frame, expected))} channel differences'
    print(f'PASS: page {page}, all 307200 visible pixels match expected text and background')
