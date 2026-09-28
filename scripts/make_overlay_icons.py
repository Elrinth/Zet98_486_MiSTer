#!/usr/bin/env python3
"""Generate rtl/assets/overlay-icons.mem: 16x16 2-bit icons for the access overlay.

Address {icon[1:0], frame[2:0], row[3:0], column[3:0]} (6144 entries):
icon 0 = 3.5" floppy turning around its vertical axis (front, edge, back),
icon 1 = CD with a shine sweeping round (spinning),
icon 2 = hard disk with a blinking activity LED.
Pixel values: 0 transparent, 1..3 per-icon palette (rtl/floppy_overlay.sv):
floppy 1 grey, 2 blue, 3 white; CD 1 lilac, 2 rainbow, 3 silver;
HDD 1 dark grey, 2 silver, 3 green LED.
Self-drawn; run without arguments, prints an ASCII preview.
"""
import math
from pathlib import Path

FRAMES = 8


def floppy_face(back):
    """16x16 Amiga-style 3.5" disk: blue body with a cut corner, white label at
    the top, grey shutter with a blue slot at the bottom (back: hub, no label).
    Floppy palette: 1 grey, 2 blue, 3 white."""
    img = [[0] * 16 for _ in range(16)]
    for y in range(1, 15):
        for x in range(1, 15):
            if x == 14 and y == 1:
                continue                                   # cut corner
            p = 2                                          # blue body
            if not back and 3 <= x <= 12 and 1 <= y <= 7:
                p = 3                                      # label
            if 4 <= x <= 11 and 10 <= y <= 14:
                p = 2 if 5 <= x <= 6 and 11 <= y <= 13 else 1   # shutter + slot
            if back and math.hypot(x - 7.5, y - 5.5) < 2.6:
                p = 3 if math.hypot(x - 7.5, y - 5.5) < 1.0 else 1   # metal hub
            if back and 2 <= x <= 3 and 2 <= y <= 3:
                p = 3                                      # write-protect tab
            img[y][x] = p
    if back:
        img = [row[::-1] for row in img]                   # seen from behind: mirrored
    return img


def floppy(frame):
    theta = 2 * math.pi * frame / FRAMES
    c = math.cos(theta)
    face = floppy_face(back=c < 0)
    width = abs(c)
    rows = [[0] * 16 for _ in range(16)]
    for y in range(16):
        for x in range(16):
            if width < 0.2:                            # edge-on: a thin disk
                if 1 <= y <= 14 and 7 <= x <= 8:
                    rows[y][x] = 1 if y in (1, 14) else 2
                continue
            sx = 7.5 + (x - 7.5) / width
            if 0 <= sx < 16:
                rows[y][x] = face[y][int(sx)]
    return rows


def cd(frame):
    """Lilac disc with rainbow bands sweeping round (spinning), silver hub.
    CD palette: 1 lilac, 2 rainbow, 3 silver."""
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            dx, dy = x - 7.5, y - 7.5
            r = math.hypot(dx, dy)
            a = (math.degrees(math.atan2(-dy, dx)) - 180 / FRAMES * frame) % 180
            if r > 7.4 or r < 1.4:
                p = 0                                      # outside / centre hole
            elif r < 2.9:
                p = 3                                      # silver hub
            elif r < 3.6:
                p = 1                                      # hub ring
            elif 30 <= a <= 48:
                p = 2                                      # rainbow band
            elif 48 < a <= 62 or 118 <= a <= 132:
                p = 3                                      # bright reflection
            else:
                p = 1                                      # lilac surface
            row.append(p)
        rows.append(row)
    return rows


def hdd(frame):
    """3.5" hard disk: dark outline, silver case, front bezel line, LED that
    blinks (on in frames 0-3 of each half). HDD palette: 1 dark, 2 silver, 3 LED."""
    led_on = frame % 4 == 0                             # on 1/4 of the time
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            if not (1 <= x <= 14 and 3 <= y <= 12):
                p = 0
            elif x in (1, 14) or y in (3, 12):
                p = 1                                      # outline
            elif y == 9:
                p = 1                                      # front bezel line
            elif y in (10, 11) and 11 <= x <= 12:
                p = 3 if led_on else 1                     # activity LED
            elif y in (5, 6) and x in (3, 12):
                p = 1                                      # screws
            else:
                p = 2                                      # silver case
            row.append(p)
        rows.append(row)
    return rows


data = []
for icon in (floppy, cd, hdd):
    for frame in range(FRAMES):
        for row in icon(frame):
            data.extend(row)
assert len(data) == 6144
out = Path(__file__).resolve().parents[1] / 'rtl/assets/overlay-icons.mem'
out.write_text(''.join('%x\n' % p for p in data), encoding='ascii')
for icon in (floppy, cd, hdd):
    frames = [icon(f) for f in range(FRAMES)]
    for y in range(16):
        print('  '.join(''.join(' .#@'[p] for p in f[y]) for f in frames))
    print()
