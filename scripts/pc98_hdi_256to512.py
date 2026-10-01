#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Convert a 256-byte-sector PC-98 HDI image into a 512-byte-sector HDI.

Old PC-98 hard-disk images (10/20/40 MB SASI disks, for example Dead of the
Brain, YU-NO or Steam Heart's releases) use 256-byte sectors, which the core's
IDE slot cannot boot. This tool rebuilds the disk with 512-byte sectors:

  python3 pc98_hdi_256to512.py "Game.hdi"        -> "Game-512b.hdi"

On Windows you can also drag the .hdi file(s) onto this script. The source
image is never modified. The DOS filesystems inside are copied unchanged;
only the partition table, the partition boot records' disk geometry fields and
the HDI header are rewritten for an 8-head, 17-sector, 512-byte-sector disk.
"""
import os
import struct
import sys

HEADS, SECTORS, BPS = 8, 17, 512
CYL_BYTES = HEADS * SECTORS * BPS
HEADER_SIZE = 4096


class ConvertError(Exception):
    pass


def parse_hdi(data):
    if len(data) < 32:
        raise ConvertError('file is too small to be an HDI image')
    _, _, offset, size, bps, spt, heads, cyl = struct.unpack_from('<8I', data)
    if not (32 <= offset <= len(data) and bps in (256, 512, 1024, 2048) and spt and heads and cyl):
        raise ConvertError('not an HDI image (unknown header)')
    payload = data[offset:offset + size]
    if len(payload) < size:
        payload += bytes(size - len(payload))  # truncated dumps: pad the missing tail
    return payload, bps, spt, heads, cyl


def valid_bpb(b):
    if len(b) < 64 or b[0] not in (0xEB, 0xE9):
        return False
    bps, spc, res, nf, roots, tot16, media, fsz = struct.unpack_from('<HBHBHHBH', b, 11)
    tot = tot16 or struct.unpack_from('<I', b, 32)[0]
    return (bps in (256, 512, 1024, 2048) and spc in (1, 2, 4, 8, 16, 32, 64, 128) and
            res >= 1 and nf in (1, 2) and roots and media >= 0xF0 and fsz and
            tot > res + nf * fsz)


def chs(e, at, heads, spt):
    """Linear 256-byte sector of a (sector, head, cylinder) field of an entry."""
    return (struct.unpack_from('<H', e, at + 2)[0] * heads + e[at + 1]) * spt + e[at]


def old_partitions(img, spt, heads):
    """PC-98 partition entries that point at a DOS boot record.
    Returns (table offset, [(index, entry, start byte)])."""
    best = None
    for table in (256, 512):
        found = []
        for i in range(8 if table == 256 else 16):
            e = img[table + i * 32:table + i * 32 + 32]
            if len(e) < 32 or not any(e[:16]):
                continue
            if e[8] >= spt or e[9] >= heads:
                continue
            start = chs(e, 8, heads, spt) * 256
            if start and valid_bpb(img[start:start + 64]):
                found.append((i, e, start))
        if found and (best is None or len(found) > len(best[1])):
            best = (table, found)
    if best is None:
        raise ConvertError('no DOS partition found in the partition table')
    return best


def patch_bpb(pbr, old_start, new_lba):
    """Rewrite the hidden-sector / geometry fields of a DOS partition boot record."""
    lbps = struct.unpack_from('<H', pbr, 11)[0]
    if lbps < 512:
        raise ConvertError('the DOS filesystem uses %d-byte sectors; use pc98_hdi_to_vhd.py '
                           'to copy the game onto a DOS VHD instead' % lbps)
    old256, old_log, new_log = old_start // 256, old_start // lbps, new_lba * BPS // lbps
    nec = ''
    if struct.unpack_from('<H', pbr, 0x44)[0] == 256 and struct.unpack_from('<I', pbr, 0x3E)[0] == old256:
        # NEC DOS boot code after the BPB: physical partition start (3Eh), data
        # area start in physical sectors (42h) and the physical sector size (44h)
        struct.pack_into('<IHH', pbr, 0x3E, new_lba, struct.unpack_from('<H', pbr, 0x42)[0] * 256 // BPS, BPS)
        nec = ' + NEC loader'
    hidden18 = struct.unpack_from('<I', pbr, 0x18)[0]
    hidden1c = struct.unpack_from('<I', pbr, 0x1C)[0]
    if struct.unpack_from('<H', pbr, 0x1E)[0] == 256 and hidden18 in (old256, old_log):
        # NEC's older layout: physical hidden sectors at 18h, physical sector size at 1Eh
        # and the data-area start in physical sectors at 1Ch (the boot code loads
        # IO.SYS from [18h]+[1Ch]; Binyu Hunter, Totsugeki! Mix).
        if hidden18 == old256:
            data = struct.unpack_from('<H', pbr, 0x1C)[0] * 256
            if data % BPS:
                raise SystemExit("the NEC boot record's data-area start is not 512-byte aligned")
            struct.pack_into('<H', pbr, 0x1C, data // BPS)
        struct.pack_into('<I', pbr, 0x18, new_lba if hidden18 == old256 else new_log)
        struct.pack_into('<H', pbr, 0x1E, BPS)
        return 'NEC' + nec
    struct.pack_into('<HH', pbr, 0x18, SECTORS, HEADS)
    struct.pack_into('<I', pbr, 0x1C, new_log if hidden1c == old_log != old256 else new_lba)
    return 'DOS' + nec


def convert(data, log=print):
    img, bps, spt, heads, cyl = parse_hdi(data)
    if bps == 512:
        raise ConvertError('this image already uses 512-byte sectors; no conversion needed')
    if bps != 256:
        raise ConvertError('this image uses %d-byte sectors; only 256-byte images are converted' % bps)
    log('source: %d cylinders, %d heads, %d sectors of 256 bytes (%.1f MB)'
        % (cyl, heads, spt, len(img) / 1048576))
    _table, parts = old_partitions(img, spt, heads)
    parts.sort(key=lambda p: p[2])

    placed = []
    next_cyl = 1                      # PC-98 hard disks start their partitions at cylinder 1
    for n, (i, e, start) in enumerate(parts):
        stop = parts[n + 1][2] if n + 1 < len(parts) else len(img)
        if e[12] == 0 and e[13] == 0:  # end given as a whole (inclusive) cylinder
            end = (struct.unpack_from('<H', e, 14)[0] + 1) * heads * spt * 256
        else:
            end = (chs(e, 12, heads, spt) + 1) * 256
        pbr = img[start:start + 64]
        lbps = struct.unpack_from('<H', pbr, 11)[0]
        tot = struct.unpack_from('<H', pbr, 19)[0] or struct.unpack_from('<I', pbr, 32)[0]
        length = min(max(min(end, stop) - start, tot * lbps), len(img) - start)
        cyls = -(-length // CYL_BYTES)
        placed.append((i, e, start, length, next_cyl, cyls))
        next_cyl += cyls
    total_cyl = next_cyl
    if total_cyl > 65535:
        raise ConvertError('image is too large')

    out = bytearray(total_cyl * CYL_BYTES)
    # Cylinder 0 keeps its byte layout (the IPL loads its menu code from 1024 on);
    # only the 256-byte sector holding the partition table moves up to 512.
    head = img[:min(parts[0][2], CYL_BYTES)]
    out[:len(head)] = head
    out[256:512] = bytes(256)
    new_table = bytearray(512)
    for i, e, start, length, c0, cyls in placed:
        dst = c0 * CYL_BYTES
        out[dst:dst + length] = img[start:start + length]
        ipl = dst + max(chs(e, 4, heads, spt) * 256 - start, 0)
        ipl_lba = ipl // BPS
        ne = bytearray(e)
        struct.pack_into('<BBH', ne, 4, ipl_lba % SECTORS, ipl_lba // SECTORS % HEADS,
                         ipl_lba // (SECTORS * HEADS))
        struct.pack_into('<BBH', ne, 8, 0, 0, c0)
        struct.pack_into('<BBH', ne, 12, 0, 0, c0 + cyls - 1)
        pbr = bytearray(out[dst:dst + 128])
        kind = patch_bpb(pbr, start, dst // BPS)
        out[dst:dst + 128] = pbr
        new_table[i * 32:i * 32 + 32] = ne
        name = bytes(ne[16:32]).rstrip(b' \0').decode('cp932', 'replace')
        log('partition %d "%s": %.1f MB at cylinder %d (%s boot record)'
            % (i + 1, name, length / 1048576, c0, kind))
    out[512:1024] = new_table
    out[510:512] = b'\x55\xaa'

    header = bytearray(HEADER_SIZE)
    struct.pack_into('<8I', header, 0, 0, 0, HEADER_SIZE, len(out), BPS, SECTORS, HEADS, total_cyl)
    log('output: %d cylinders, 8 heads, 17 sectors of 512 bytes (%.1f MB)'
        % (total_cyl, len(out) / 1048576))
    return bytes(header) + bytes(out)


def output_name(path):
    root, ext = os.path.splitext(path)
    return root + '-512b' + (ext if ext.lower() == '.hdi' else '.hdi')


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    status = 0
    for path in argv:
        print('\n' + path)
        try:
            with open(path, 'rb') as f:
                data = f.read()
            result = convert(data)
            target = output_name(path)
            if os.path.exists(target):
                raise ConvertError('%s already exists; not overwriting it' % target)
            with open(target, 'wb') as f:
                f.write(result)
            print('written: ' + target)
        except (ConvertError, OSError) as err:
            print('WARNING: %s' % err)
            status = 1
    return status


if __name__ == '__main__':
    code = main(sys.argv[1:])
    if os.name == 'nt' and len(sys.argv) > 1:   # keep a drag-and-drop window open
        try:
            input('\nPress Enter to close...')
        except EOFError:
            pass
    sys.exit(code)
