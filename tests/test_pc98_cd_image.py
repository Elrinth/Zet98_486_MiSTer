#!/usr/bin/env python3
"""Synthetic CUE/BIN discs through scripts/pc98_cd_image.py; checks header and sectors."""
import os, struct, sys, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
import pc98_cd_image as pcd

def pattern(tag, lba, size):
    return bytes(((tag * 31 + lba * 7 + i) & 255) for i in range(size))

def check(cond, what):
    if not cond:
        sys.exit('FAIL: ' + what)

with tempfile.TemporaryDirectory() as d:
    # 1) single file: MODE1/2352 data (50) + AUDIO (30), INDEX 00 pregap of 5 on track 2
    raw = b''.join(pattern(1, i, 2352) for i in range(85))
    open(os.path.join(d, 'one.bin'), 'wb').write(raw)
    open(os.path.join(d, 'one.cue'), 'w').write(
        'FILE "one.bin" BINARY\n  TRACK 01 MODE1/2352\n    INDEX 01 00:00:00\n'
        '  TRACK 02 AUDIO\n    INDEX 00 00:00:50\n    INDEX 01 00:00:55\n')
    table, lo = pcd.convert(os.path.join(d, 'one.cue'), os.path.join(d, 'one.pcd'))
    img = open(os.path.join(d, 'one.pcd'), 'rb').read()
    check(img[:8] == b'PC98CD01' and img[8] == 2 and struct.unpack_from('<I', img, 12)[0] == 85, 'single header')
    t1, t2 = struct.unpack_from('<II', img, 16)
    check(t1 == 0x14 and t2 == (0x10 | (55 << 8)), 'single track table %x %x' % (t1, t2))
    check(img[2352:] == raw, 'single sectors copied verbatim')
    # 2) multi file: MODE1/2048 data (40) + AUDIO file (20, INDEX 00 10 frames) + PREGAP 00:00:03 AUDIO (12)
    data = b''.join(pattern(2, i, 2048) for i in range(40))
    a2 = b''.join(pattern(3, i, 2352) for i in range(20))
    a3 = b''.join(pattern(4, i, 2352) for i in range(12))
    for n, b in (('t1.bin', data), ('t2.bin', a2), ('t3.bin', a3)):
        open(os.path.join(d, n), 'wb').write(b)
    open(os.path.join(d, 'multi.cue'), 'w').write(
        'FILE "t1.bin" BINARY\n  TRACK 01 MODE1/2048\n    INDEX 01 00:00:00\n'
        'FILE "t2.bin" BINARY\n  TRACK 02 AUDIO\n    INDEX 00 00:00:00\n    INDEX 01 00:00:10\n'
        'FILE "t3.bin" BINARY\n  TRACK 03 AUDIO\n    PREGAP 00:00:03\n    INDEX 01 00:00:00\n')
    table, lo = pcd.convert(os.path.join(d, 'multi.cue'), os.path.join(d, 'multi.pcd'))
    img = open(os.path.join(d, 'multi.pcd'), 'rb').read()
    # track 1 @0 (40), track-2 INDEX 00 pregap 10 sectors @40, track 2 @50, pregap 3 @60, track 3 @63, lead-out 75
    check(img[8] == 3 and struct.unpack_from('<I', img, 12)[0] == 75, 'multi header %d' % struct.unpack_from('<I', img, 12)[0])
    ents = struct.unpack_from('<III', img, 16)
    check(ents == (0x14, 0x10 | (50 << 8), 0x10 | (63 << 8)), 'multi track table %r' % (ents,))
    sec = lambda lba: img[2352 * (lba + 1): 2352 * (lba + 2)]
    check(sec(7)[16:2064] == pattern(2, 7, 2048) and sec(7)[:12] == b'\x00' + b'\xff' * 10 + b'\x00', 'MODE1/2048 wrapped')
    check(sec(7)[12:16] == bytes([0, 2, 0x07, 1]), 'wrapped BCD header')
    check(sec(40) == pattern(3, 0, 2352) and sec(50) == pattern(3, 10, 2352), 'audio file with INDEX 00 pregap')
    check(sec(60) == bytes(2352) and sec(62) == bytes(2352) and sec(63) == pattern(4, 0, 2352), 'PREGAP silence')
    check(len(img) == 2352 * 76, 'image size')
    lead = struct.unpack_from('<I', img, 16 + 12)[0]
    check(lead == 0x10 | (75 << 8), 'lead-out entry %x' % lead)
    check(struct.unpack_from('>IIII', img, 512) == (0, 50, 63, 75), 'LBA table')
    check(img[1024 + 4:1024 + 8] == bytes([0, 0, 2, 50]) and img[1024 + 12:1024 + 16] == bytes([0, 0, 3, 0]), 'MSF table')
    check(img[1536 + 4:1536 + 8] == bytes([0, 0, 2, 0x50]) and img[1536 + 12:1536 + 16] == bytes([0, 0, 3, 0]), 'BCD table')
print('PASS: pc98_cd_image: single-file and multi-file CUE, MODE1/2048 wrap, INDEX 00, PREGAP, track table, TOC address tables')
