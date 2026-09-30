#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Insert a PC-98 sound BIOS ROM (16 KB, e.g. NP2kai's SOUND.ROM) into boot.rom.

The core maps boot.rom offset 20000h-23FFFh at CC000h. When that area is
blank it shows a stub instead (enough for programs that only check for the
sound BIOS); with a real ROM there, INT D2h calls run the real routines.

Usage: pc98_insert_sound_rom.py boot.rom sound.rom [output.rom]
Writes output.rom (default: boot.rom with .snd appended); never edits in place.
"""
import sys

OFFSET = 0x20000
SIZE = 0x4000
BOOT_SIZE = 550912


def main(argv):
    if len(argv) not in (3, 4):
        print(__doc__)
        return 2
    boot = bytearray(open(argv[1], 'rb').read())
    sound = open(argv[2], 'rb').read()
    if len(boot) != BOOT_SIZE:
        print(f'{argv[1]}: expected {BOOT_SIZE} bytes, got {len(boot)}')
        return 1
    if len(sound) != SIZE:
        print(f'{argv[2]}: expected a {SIZE}-byte sound ROM, got {len(sound)}')
        return 1
    if sound[0x2e00:0x2e06] != bytes([1, 0, 0, 0, 0xd2, 0]):
        print(f'{argv[2]}: no sound BIOS header (01 00 00 00 D2 00) at 2E00h')
        return 1
    boot[OFFSET:OFFSET + SIZE] = sound
    out = argv[3] if len(argv) == 4 else argv[1] + '.snd'
    open(out, 'wb').write(boot)
    print(f'wrote {out}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
