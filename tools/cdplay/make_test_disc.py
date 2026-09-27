#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build PC98CDAUDIO.cue/.bin/.pcd: a CD-audio test disc for the PC98 core.

Track 1: ISO 9660 data track with CDPLAY.COM (tools/cdplay).
Track 2: 12 s, 440 Hz in both channels.
Track 3: 12 s, 660 Hz left / 880 Hz right.
Usage: make_test_disc.py CDPLAY.COM out_dir
"""
import math, os, struct, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'scripts'))
import pc98_cd_image

SEC = 2048


def both16(v):
    return struct.pack('<H', v) + struct.pack('>H', v)


def both32(v):
    return struct.pack('<I', v) + struct.pack('>I', v)


def dirrec(name, lba, size, is_dir):
    rec = bytearray(33 + len(name) + (1 - len(name) % 2))
    rec[0] = len(rec)
    rec[2:10] = both32(lba)
    rec[10:18] = both32(size)
    rec[18:25] = bytes([95, 1, 1, 0, 0, 0, 0])
    rec[25] = 2 if is_dir else 0
    rec[28:32] = both16(1)
    rec[32] = len(name)
    rec[33:33 + len(name)] = name
    return bytes(rec)


def iso(files):
    """files: list of (8.3 name, bytes) in the root directory."""
    root_lba, pt_lba, first = 20, 19, 21
    layout, lba = [], first
    for name, data in files:
        layout.append((name, lba, data))
        lba += max(1, (len(data) + SEC - 1) // SEC)
    total = lba
    root = dirrec(b'\x00', root_lba, SEC, True) + dirrec(b'\x01', root_lba, SEC, True)
    for name, flba, data in layout:
        root += dirrec(name.encode() + b';1', flba, len(data), False)
    root = root.ljust(SEC, b'\x00')
    pvd = bytearray(SEC)
    pvd[0] = 1
    pvd[1:6] = b'CD001'
    pvd[6] = 1
    pvd[8:40] = b' ' * 32
    pvd[40:72] = b'PC98CDAUDIO'.ljust(32)
    pvd[80:88] = both32(total)
    pvd[120:124] = both16(1)
    pvd[124:128] = both16(1)
    pvd[128:132] = both16(SEC)
    pvd[132:140] = both32(10)
    pvd[140:144] = struct.pack('<I', pt_lba)
    pvd[148:152] = struct.pack('>I', pt_lba - 1)
    pvd[156:190] = dirrec(b'\x00', root_lba, SEC, True)
    for off, n in ((190, 128), (318, 128), (446, 128), (574, 128), (702, 37), (739, 37), (776, 37)):
        pvd[off:off + n] = b' ' * n
    for off in (813, 830, 847, 864):
        pvd[off:off + 17] = b'0' * 16 + b'\x00'
    pvd[881] = 1
    term = bytearray(SEC)
    term[0] = 255
    term[1:6] = b'CD001'
    term[6] = 1
    # Path tables (one entry, the root): big-endian at 18, little-endian at 19.
    pt, ptm = bytearray(SEC), bytearray(SEC)
    pt[0] = ptm[0] = 1
    pt[2:6] = struct.pack('<I', root_lba)
    pt[6:8] = struct.pack('<H', 1)
    ptm[2:6] = struct.pack('>I', root_lba)
    ptm[6:8] = struct.pack('>H', 1)
    img = bytearray(SEC * 16) + pvd + term + ptm + pt + root
    assert len(img) == SEC * first
    for name, flba, data in layout:
        img += data.ljust(max(1, (len(data) + SEC - 1) // SEC) * SEC, b'\x00')
    return bytes(img)


def tone(seconds, fl, fr):
    n = int(44100 * seconds)
    n -= n % 588
    out = bytearray()
    for i in range(n):
        env = min(1.0, i / 2205, (n - i) / 2205)
        l = int(12000 * env * math.sin(2 * math.pi * fl * i / 44100))
        r = int(12000 * env * math.sin(2 * math.pi * fr * i / 44100))
        out += struct.pack('<hh', l, r)
    return bytes(out)


def main():
    com, out = sys.argv[1], sys.argv[2]
    readme = (b'PC98 core CD audio test disc\r\n'
              b'CDPLAY 2  plays 440 Hz (both channels)\r\n'
              b'CDPLAY 3  plays 660 Hz left, 880 Hz right\r\n')
    data = iso([('CDPLAY.COM', open(com, 'rb').read()), ('README.TXT', readme)])
    data = data.ljust(SEC * 300, b'\x00')          # a 4-second data track
    names = ('PC98CDAUDIO_1.bin', 'PC98CDAUDIO_2.bin', 'PC98CDAUDIO_3.bin')
    open(os.path.join(out, names[0]), 'wb').write(data)
    open(os.path.join(out, names[1]), 'wb').write(tone(12, 440, 440))
    open(os.path.join(out, names[2]), 'wb').write(tone(12, 660, 880))
    cue = ('FILE "%s" BINARY\n  TRACK 01 MODE1/2048\n    INDEX 01 00:00:00\n'
           'FILE "%s" BINARY\n  TRACK 02 AUDIO\n    PREGAP 00:02:00\n    INDEX 01 00:00:00\n'
           'FILE "%s" BINARY\n  TRACK 03 AUDIO\n    INDEX 01 00:00:00\n') % names
    cue_path = os.path.join(out, 'PC98CDAUDIO.cue')
    open(cue_path, 'w').write(cue)
    pcd = os.path.join(out, 'PC98CDAUDIO.pcd')
    if os.path.exists(pcd):
        os.remove(pcd)
    table, leadout = pc98_cd_image.convert(cue_path, pcd)
    print('tracks', table, 'lead-out', leadout, '->', pcd)


if __name__ == '__main__':
    main()
