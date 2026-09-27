#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Convert a CUE sheet (+ BIN files) into one .PCD image for the PC98 core's CD-ROM.

MiSTer mounts one file per slot, so the track layout that a CUE sheet keeps in
a separate text file is stored in a header instead:

  offset 0      2352-byte header sector (only the first 512 bytes are used)
                  0  "PC98CD01"
                  8  track count            9  first track number (1)
                 12  lead-out LBA (u32 LE)
                 16  4 bytes per track: control (14h data, 10h audio),
                     start LBA (u24 LE; bit 23 = MODE2, user data at +24);
                     entry [track count] is the lead-out
                512  per entry (tracks, then lead-out) the READ TOC address
                     fields: LBA (u32 BE) at 512+4i, MSF 00 M S F at 1024+4i,
                     the same in BCD at 1536+4i
  offset 2352   disc sector 0, 1, ... as raw 2352-byte sectors

MODE1/2048 tracks are wrapped into raw sectors (sync, BCD MSF header, mode 1,
zero EDC/ECC); PREGAP adds silence; INDEX 01 marks each track start.
Usage: pc98_cd_image.py game.cue [game.pcd]
"""
import os, re, struct, sys

RAW = 2352


def msf_to_frames(t):
    m, s, f = (int(x) for x in t.split(':'))
    return (m * 60 + s) * 75 + f


def bcd(v):
    return (v // 10) * 16 + v % 10


def raw_from_2048(data, lba):
    f = lba + 150
    head = b'\x00' + b'\xff' * 10 + b'\x00' + bytes([bcd(f // 4500), bcd((f // 75) % 60), bcd(f % 75), 1])
    return head + data + bytes(288)


def parse_cue(path):
    """-> list of files: {name, tracks: [{number, mode, index1, pregap}]}"""
    files = []
    base = os.path.dirname(os.path.abspath(path))
    for line in open(path, encoding='latin-1'):
        line = line.strip()
        if not line:
            continue
        m = re.match(r'FILE\s+"?(.+?)"?\s+(\w+)$', line, re.I)
        if m:
            files.append({'name': os.path.join(base, m.group(1)), 'tracks': []})
            continue
        m = re.match(r'TRACK\s+(\d+)\s+(\S+)', line, re.I)
        if m:
            files[-1]['tracks'].append({'number': int(m.group(1)), 'mode': m.group(2).upper(),
                                        'index1': None, 'pregap': 0})
            continue
        m = re.match(r'INDEX\s+(\d+)\s+(\S+)', line, re.I)
        if m and int(m.group(1)) == 1:
            files[-1]['tracks'][-1]['index1'] = msf_to_frames(m.group(2))
            continue
        m = re.match(r'PREGAP\s+(\S+)', line, re.I)
        if m:
            files[-1]['tracks'][-1]['pregap'] = msf_to_frames(m.group(1))
    return files


def sector_size(mode):
    if mode in ('MODE1/2048', 'MODE2/2048'):
        return 2048
    if mode in ('MODE1/2352', 'MODE2/2352', 'AUDIO'):
        return RAW
    raise ValueError('unsupported track mode ' + mode)


def convert(cue, out):
    files = parse_cue(cue)
    sectors = []          # list of raw 2352-byte sectors (lazy: (file, offset, size, mode))
    table = []
    for f in files:
        size = os.path.getsize(f['name'])
        tracks = f['tracks']
        if not tracks:
            continue
        ssize = sector_size(tracks[0]['mode'])
        if any(sector_size(t['mode']) != ssize for t in tracks):
            raise ValueError('mixed sector sizes within one FILE are not supported')
        if size % ssize:
            raise ValueError('%s is not a whole number of %d-byte sectors' % (f['name'], ssize))
        file_sectors = size // ssize
        for i, t in enumerate(tracks):
            if t['index1'] is None:
                raise ValueError('track %d has no INDEX 01' % t['number'])
            start_in_file = t['index1']
            if t['pregap']:
                sectors.extend([('silence',)] * t['pregap'])
            # A track spans INDEX 01 up to the next track's INDEX 01 (its INDEX 00
            # pregap stays with the previous track, as on the disc).
            end = tracks[i + 1]['index1'] if i + 1 < len(tracks) else file_sectors
            # sectors before INDEX 01 of the first track in a file (INDEX 00 pregap)
            if i == 0 and start_in_file > 0:
                for k in range(start_in_file):
                    sectors.append((f['name'], k * ssize, ssize, t['mode']))
            table.append((t['number'], 0x10 if t['mode'] == 'AUDIO' else 0x14,
                          len(sectors), t['mode'].startswith('MODE2')))
            for k in range(start_in_file, end):
                sectors.append((f['name'], k * ssize, ssize, t['mode']))
    if not table or len(table) > 99:
        raise ValueError('need 1-99 tracks')
    leadout = len(sectors)
    header = bytearray(RAW)
    header[0:8] = b'PC98CD01'
    header[8] = len(table)
    header[9] = table[0][0]
    struct.pack_into('<I', header, 12, leadout)
    if leadout >= 1 << 20:
        raise ValueError('disc too long')
    entries = [(ctrl, lba, mode2) for _, ctrl, lba, mode2 in table] + [(table[-1][1], leadout, False)]
    for i, (ctrl, lba, mode2) in enumerate(entries):
        struct.pack_into('<I', header, 16 + 4 * i, ctrl | (lba << 8) | (0x80000000 if mode2 else 0))
        struct.pack_into('>I', header, 512 + 4 * i, lba)
        f = lba + 150
        m, sec, fr = f // 4500, (f // 75) % 60, f % 75
        header[1024 + 4 * i:1028 + 4 * i] = bytes([0, m, sec, fr])
        header[1536 + 4 * i:1540 + 4 * i] = bytes([0, bcd(m), bcd(sec), bcd(fr)])
    handles = {}
    with open(out, 'wb') as o:
        o.write(header)
        for lba, s in enumerate(sectors):
            if s[0] == 'silence':
                o.write(bytes(RAW))
                continue
            name, off, size, mode = s
            h = handles.get(name) or handles.setdefault(name, open(name, 'rb'))
            h.seek(off)
            data = h.read(size)
            o.write(data if size == RAW else raw_from_2048(data, lba))
    for h in handles.values():
        h.close()
    return table, leadout


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    cue = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) == 3 else os.path.splitext(cue)[0] + '.pcd'
    if os.path.exists(out):
        sys.exit('refusing to overwrite ' + out)
    table, leadout = convert(cue, out)
    for num, ctrl, lba, mode2 in table:
        f = lba + 150
        print('track %2d %-5s LBA %6d  %02d:%02d:%02d' % (num, 'audio' if ctrl == 0x10 else 'data',
              lba, f // 4500, (f // 75) % 60, f % 75))
    print('lead-out LBA %d; wrote %s (%d bytes)' % (leadout, out, os.path.getsize(out)))


if __name__ == '__main__':
    main()
