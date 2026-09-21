#!/usr/bin/env python3
"""Package our BIOS-first IPL/resident loader as a new write-protected D88.

Assemble tests/hardware/ide_bootsector.asm and ide_bootstrap.asm (-DBIOS_BOOT=1)
first. This disk contains only those binaries and zero fill, no DOS/game data.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from import_disk_image import make_d88, d88_tracks


def package(ipl, loader):
    if len(ipl) != 1024 or not 0 < len(loader) <= 4096:
        raise ValueError('Expected a 1024-byte IPL and a resident loader of at most 4096 bytes')
    raw = ipl + loader.ljust(4096, b'\0') + bytes(1261568 - 5120)
    tracks = []
    for cylinder in range(77):
        for head in range(2):
            records = []
            for sector in range(1, 9):
                offset = ((cylinder * 2 + head) * 8 + sector - 1) * 1024
                records.append((cylinder, head, sector, 3, 0, False, raw[offset:offset+1024]))
            tracks.append(records)
    data = make_d88(tracks, 'Z98 VHD boot', 0x20, protected=True)
    assert b''.join(payload for track in d88_tracks(data) for _, payload in track) == raw
    return data


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipl', type=Path)
    parser.add_argument('loader', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    data = package(args.ipl.read_bytes(), args.loader.read_bytes())
    with args.output.open('xb') as output:
        output.write(data)
    print('Wrote new write-protected BIOS-first bootstrap floppy:', args.output)
