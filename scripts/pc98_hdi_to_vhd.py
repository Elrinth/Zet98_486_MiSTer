#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Move a PC-98 game from any hard-disk image onto your own DOS VHD.

Old PC-98 hard-disk images (for example 10/20/40 MB SASI HDI files from
Anex86 or early NP2) use 256-byte sectors, which the core's IDE slot cannot
boot. Their DOS filesystem does not depend on that sector size, so this tool
copies the files instead of the disk:

  python scripts/pc98_hdi_to_vhd.py list    game.hdi
  python scripts/pc98_hdi_to_vhd.py extract game.hdi out_folder
  python scripts/pc98_hdi_to_vhd.py copy    game.hdi my_dos.vhd GAMEDIR

`copy` writes into GAMEDIR on the first DOS partition of a 512-byte-sector
FAT16 image (a VHD/IMG that already boots on the core). The source's own DOS
system files (IO.SYS, MSDOS.SYS, COMMAND.COM, ...) are skipped; its root
CONFIG.SYS and AUTOEXEC.BAT are kept as CONFIG.ORG and AUTOEXEC.ORG so you can
see which drivers the game expects. Use --all to copy everything. The source
image is never modified; back up the target VHD before `copy`.

Accepted sources: HDI (any sector size), NHD, or raw images. Names are kept as
raw 8.3 bytes, so Shift-JIS file names survive.
"""
import argparse
import os
import struct
import sys
import time

SYSTEM_FILES = {b'IO      SYS', b'MSDOS   SYS', b'COMMAND COM', b'IO98    SYS',
                b'MEGDOS  SYS', b'DBLSPACEBIN', b'DRVSPACEBIN', b'MSDOS   ---'}
RENAMED = {b'CONFIG  SYS': b'CONFIG  ORG', b'AUTOEXECBAT': b'AUTOEXECORG'}


def image_payload(data):
    """Strip an HDI/NHD header; return (payload, physical sector size or None)."""
    if len(data) >= 32 and data[:4] == b'\0\0\0\0':
        _, _, offset, size, bps, spt, heads, cyl = struct.unpack_from('<8I', data)
        if 32 <= offset <= len(data) and bps in (256, 512, 1024) and size == bps*spt*heads*cyl:
            return data[offset:offset+size], bps
    if data.startswith(b'T98HDDIMAGE.R0'):
        offset, cyl, heads, spt, bps = struct.unpack_from('<IIHHH', data, 0x110)
        return data[offset:], bps
    return data, None


def valid_bpb(b):
    if len(b) < 64 or b[0] not in (0xEB, 0xE9):
        return False
    bps, spc, res, nf, roots, tot16, media, fsz = struct.unpack_from('<HBHBHHBH', b, 11)
    tot = tot16 or struct.unpack_from('<I', b, 32)[0]
    return (bps in (256, 512, 1024, 2048) and spc in (1, 2, 4, 8, 16, 32, 64, 128) and
            res >= 1 and nf in (1, 2) and roots and roots % (bps//32) == 0 and
            media >= 0xF0 and fsz and tot > res + nf*fsz)


def find_partition(img, step, what):
    """First sector (in `step` units, within 4 MB) holding a DOS boot sector."""
    for off in range(step, min(len(img), 4 << 20), step):
        if valid_bpb(img[off:off+64]):
            return off
    raise SystemExit('no DOS partition found in the %s image' % what)


class FatReader:
    """Read-only FAT12/FAT16 with any logical sector size."""

    def __init__(self, img, part):
        b = img[part:part+64]
        self.img, self.part = img, part
        (self.bps, self.spc, res, nf, self.roots, tot16, _media, fsz) = struct.unpack_from('<HBHBHHBH', b, 11)
        tot = tot16 or struct.unpack_from('<I', b, 32)[0]
        self.fat_at = part + res*self.bps
        self.root_at = self.fat_at + nf*fsz*self.bps
        self.data_at = self.root_at + ((self.roots*32 + self.bps - 1)//self.bps)*self.bps
        self.cl = self.bps*self.spc
        clusters = (part + tot*self.bps - self.data_at)//self.cl
        self.fat12 = clusters < 4085
        self.fat = img[self.fat_at:self.fat_at + fsz*self.bps]

    def next(self, c):
        if self.fat12:
            v = struct.unpack_from('<H', self.fat, c*3//2)[0]
            v = v >> 4 if c & 1 else v & 0xFFF
            return v if v < 0xFF8 else None
        v = struct.unpack_from('<H', self.fat, c*2)[0]
        return v if v < 0xFFF8 else None

    def chain(self, c):
        seen = set()
        while c is not None and 2 <= c and c not in seen:
            seen.add(c)
            yield c
            c = self.next(c)

    def read(self, start, size=None):
        out = b''.join(self.img[self.data_at+(c-2)*self.cl:self.data_at+(c-1)*self.cl]
                       for c in self.chain(start))
        return out if size is None else out[:size]

    def entries(self, dirc):
        raw = self.img[self.root_at:self.root_at+self.roots*32] if dirc == 0 else self.read(dirc)
        for i in range(0, len(raw), 32):
            e = raw[i:i+32]
            if e[0] == 0:
                return
            if e[0] == 0xE5 or e[11] == 0x0F or e[11] & 0x08 or e[:2] in (b'. ', b'..'):
                continue
            name = (b'\xe5' + e[1:11]) if e[0] == 0x05 else e[:11]
            yield name, e[11], struct.unpack_from('<H', e, 26)[0], struct.unpack_from('<I', e, 28)[0], e

    def walk(self, dirc=0, path=()):
        for name, attr, start, size, e in self.entries(dirc):
            if attr & 0x10:
                yield path + (name,), None, e
                yield from self.walk(start, path + (name,))
            else:
                yield path + (name,), self.read(start, size), e


def display(name11):
    base, ext = name11[:8].rstrip(b' '), name11[8:].rstrip(b' ')
    text = (base + (b'.' + ext if ext else b'')).decode('cp932', 'replace')
    return text


def dos_time(e):
    t, d = struct.unpack_from('<HH', e, 22)
    try:
        return time.mktime(((d >> 9) + 1980, (d >> 5) & 15, d & 31, t >> 11, (t >> 5) & 63, (t & 31)*2, 0, 0, -1))
    except (OverflowError, ValueError):
        return time.time()


def select(files, keep_all):
    for path, data, e in files:
        if not keep_all and len(path) == 1:
            if path[0] in SYSTEM_FILES:
                continue
            if path[0] in RENAMED:
                path = (RENAMED[path[0]],)
        yield path, data, e


def open_source(name):
    img, bps = image_payload(open(name, 'rb').read())
    part = find_partition(img, bps or 256, 'source')
    return FatReader(img, part)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('mode', choices=('list', 'extract', 'copy'))
    ap.add_argument('source')
    ap.add_argument('target', nargs='?')
    ap.add_argument('directory', nargs='?', help='copy: 8.3 directory name on the target')
    ap.add_argument('--all', action='store_true', help='also copy DOS system files and root CONFIG/AUTOEXEC')
    a = ap.parse_args()
    fs = open_source(a.source)
    print('source: %d-byte logical sectors, %s' % (fs.bps, 'FAT12' if fs.fat12 else 'FAT16'))
    files = list(select(fs.walk(), a.all))
    if a.mode == 'list':
        for path, data, _ in files:
            print(('%10d ' % len(data) if data is not None else '     <DIR> ') + '\\'.join(map(display, path)))
        return
    if a.mode == 'extract':
        if not a.target:
            ap.error('extract needs an output folder')
        for path, data, e in files:
            out = os.path.join(a.target, *map(display, path))
            if data is None:
                os.makedirs(out, exist_ok=True)
            else:
                os.makedirs(os.path.dirname(out), exist_ok=True)
                with open(out, 'wb') as f:
                    f.write(data)
                os.utime(out, (dos_time(e),)*2)
        print('extracted %d files to %s' % (sum(d is not None for _, d, _ in files), a.target))
        return
    if not (a.target and a.directory):
        ap.error('copy needs a target image and a directory name')
    from fat16_writer import Fat16, name11
    with open(a.target, 'rb') as f:
        head = f.read(4 << 20)
    tpart = find_partition(head, 512, 'target')
    target = Fat16(a.target, tpart)
    if target.nclusters < 4085:
        raise SystemExit('the target partition is FAT12; use a FAT16 DOS partition')
    need = sum(-(-len(d)//target.cl)*target.cl for _, d, _ in files if d is not None)
    if need > target.free_bytes():
        raise SystemExit('not enough free space on the target (%d KB needed)' % (need//1024))
    top = target.mkdir(0, name11(a.directory.encode('cp932')), time.time())
    dirs = {(): top}
    count = 0
    for path, data, e in files:
        parent = dirs[path[:-1]]
        if data is None:
            dirs[path] = target.mkdir(parent, path[-1], dos_time(e))
        else:
            target.put(parent, path[-1], data, dos_time(e), attr=(e[11] & 0x27) or 0x20)
            count += 1
    target.flush()
    print('copied %d files into \\%s on %s' % (count, a.directory.upper(), a.target))


if __name__ == '__main__':
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    main()
