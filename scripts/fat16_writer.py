# SPDX-License-Identifier: GPL-3.0-or-later
"""Minimal FAT16 writer for PC-98 DOS VHD/IMG partitions (512-byte sectors).

Writes exact 8.3 short names (raw bytes, so Shift-JIS names survive) and no
long-file-name entries. Supports mkdir, put (create or replace) and read-back.
"""
import os, struct, time

class Fat16:
    def __init__(self, path, part):
        self.f = open(path, 'r+b')
        self.part = part
        self.f.seek(part)
        bs = self.f.read(512)
        (self.bps, self.spc, self.res, self.nf, self.roots, tot16, _media,
         self.fsz) = struct.unpack_from('<HBHBHHBH', bs, 11)
        tot = tot16 or struct.unpack_from('<I', bs, 32)[0]
        self.fat_at = part + self.res * self.bps
        self.root_at = self.fat_at + self.nf * self.fsz * self.bps
        self.data_at = self.root_at + self.roots * 32
        self.cl = self.bps * self.spc
        root_sectors = (self.roots * 32 + self.bps - 1) // self.bps
        self.nclusters = (tot - self.res - self.nf * self.fsz - root_sectors) // self.spc
        self.f.seek(self.fat_at)
        raw = self.f.read(self.fsz * self.bps)
        self.fat = list(struct.unpack('<%dH' % (len(raw) // 2), raw))
        self.next_free = 2

    # --- clusters -------------------------------------------------------
    def chain(self, c):
        out = []
        while 2 <= c < 0xfff8:
            out.append(c); c = self.fat[c]
        return out

    def alloc(self, n):
        got = []
        c = self.next_free
        while len(got) < n:
            if c >= self.nclusters + 2:
                raise RuntimeError('disk full')
            if self.fat[c] == 0:
                got.append(c)
            c += 1
        self.next_free = c
        for a, b in zip(got, got[1:]):
            self.fat[a] = b
        if got:
            self.fat[got[-1]] = 0xffff
        return got

    def free_chain(self, c):
        for x in self.chain(c):
            self.fat[x] = 0
            self.next_free = min(self.next_free, x)

    def coff(self, c):
        return self.data_at + (c - 2) * self.cl

    def write_clusters(self, clusters, data):
        for i, c in enumerate(clusters):
            chunk = data[i * self.cl:(i + 1) * self.cl]
            self.f.seek(self.coff(c))
            self.f.write(chunk + bytes(self.cl - len(chunk)))

    def read_file(self, start, size):
        d = b''
        for c in self.chain(start):
            self.f.seek(self.coff(c)); d += self.f.read(self.cl)
        return d[:size]

    # --- directories ------------------------------------------------------
    def dir_slots(self, dirc):
        """List of absolute byte offsets of each 32-byte slot in a directory."""
        if dirc == 0:
            return [self.root_at + i * 32 for i in range(self.roots)]
        out = []
        for c in self.chain(dirc):
            base = self.coff(c)
            out += [base + i * 32 for i in range(self.cl // 32)]
        return out

    def entries(self, dirc):
        for off in self.dir_slots(dirc):
            self.f.seek(off); e = self.f.read(32)
            if e[0] == 0:
                return
            if e[0] == 0xe5 or e[11] == 0x0f:
                continue
            yield off, e

    def find(self, dirc, name11):
        for off, e in self.entries(dirc):
            n = e[:11]
            if n[0] == 0x05:
                n = b'\xe5' + n[1:]
            if n == name11:
                return off, e
        return None

    def free_slot(self, dirc):
        for off in self.dir_slots(dirc):
            self.f.seek(off)
            b = self.f.read(1)[0]
            if b in (0, 0xe5):
                return off
        if dirc == 0:
            raise RuntimeError('root directory full')
        c = self.alloc(1)[0]
        self.fat[self.chain(dirc)[-1]] = c
        self.fat[c] = 0xffff
        self.write_clusters([c], b'')
        return self.coff(c)

    @staticmethod
    def stamp(t):
        lt = time.localtime(t)
        y = max(lt.tm_year, 1980)
        return ((lt.tm_hour << 11) | (lt.tm_min << 5) | (lt.tm_sec // 2),
                ((y - 1980) << 9) | (lt.tm_mon << 5) | lt.tm_mday)

    def make_entry(self, name11, attr, start, size, mtime):
        n = name11
        if n[0] == 0xe5:
            n = b'\x05' + n[1:]
        t, d = self.stamp(mtime)
        return n + bytes([attr]) + bytes(10) + struct.pack('<HHHI', t, d, start, size)

    def mkdir(self, parent, name11, mtime):
        hit = self.find(parent, name11)
        if hit:
            if not hit[1][11] & 0x10:
                raise RuntimeError('file exists where directory wanted: %r' % name11)
            return struct.unpack_from('<H', hit[1], 26)[0]
        c = self.alloc(1)[0]
        body = (self.make_entry(b'.          ', 0x10, c, 0, mtime) +
                self.make_entry(b'..         ', 0x10, parent, 0, mtime))
        self.write_clusters([c], body)
        off = self.free_slot(parent)
        self.f.seek(off); self.f.write(self.make_entry(name11, 0x10, c, 0, mtime))
        return c

    def put(self, parent, name11, data, mtime, attr=0x20):
        hit = self.find(parent, name11)
        if hit:
            off, e = hit
            if e[11] & 0x10:
                raise RuntimeError('directory exists where file wanted: %r' % name11)
            self.free_chain(struct.unpack_from('<H', e, 26)[0])
        else:
            off = self.free_slot(parent)
        n = (len(data) + self.cl - 1) // self.cl
        clusters = self.alloc(n) if n else []
        self.write_clusters(clusters, data)
        self.f.seek(off)
        self.f.write(self.make_entry(name11, attr, clusters[0] if clusters else 0, len(data), mtime))

    def flush(self):
        raw = struct.pack('<%dH' % len(self.fat), *self.fat)
        for i in range(self.nf):
            self.f.seek(self.fat_at + i * self.fsz * self.bps)
            self.f.write(raw)
        self.f.flush(); os.fsync(self.f.fileno())

    def free_bytes(self):
        return sum(1 for c in range(2, self.nclusters + 2) if self.fat[c] == 0) * self.cl


def name11(raw):
    """raw: bytes of a DOS 8.3 name (may contain Shift-JIS)."""
    if raw in (b'.', b'..'):
        raise ValueError
    if b'.' in raw:
        base, ext = raw.rsplit(b'.', 1)
    else:
        base, ext = raw, b''
    up = lambda b: bytes(x - 32 if 0x61 <= x <= 0x7a else x for x in b)
    base, ext = up(base), up(ext)
    if not 1 <= len(base) <= 8 or len(ext) > 3:
        raise ValueError('not 8.3: %r' % raw)
    return base.ljust(8, b' ') + ext.ljust(3, b' ')

