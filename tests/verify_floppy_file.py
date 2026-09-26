#!/usr/bin/env python3
"""Audit a newly created diagnostic file on an isolated FAT12 D88 copy.

Check the persisted pattern and allow changes only to the new file's
directory entry, previously free FAT links, and newly allocated clusters.
"""
from pathlib import Path
import argparse
import math
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from d88_file import D88


def fat_entry(fat, cluster):
    offset = cluster * 3 // 2
    word = int.from_bytes(fat[offset:offset + 2], 'little')
    return word >> 4 if cluster & 1 else word & 0xfff


def audit(before_path, after_path, filename='Z98WRITE.BIN', expected=None):
    filename = filename.upper()
    assert re.fullmatch(r'[A-Z0-9_]{1,8}\.[A-Z0-9_]{1,3}', filename), 'Expected a plain DOS 8.3 filename'
    if expected is None:
        assert filename == 'Z98WRITE.BIN', 'A custom filename requires an expected payload'
        expected = bytes(((i // 1024) + (i % 1024) * 37) & 255 for i in range(70001))
    assert expected, 'Expected a nonempty diagnostic payload'
    before, after = D88(before_path), D88(after_path)
    assert before.sectors == after.sectors, 'D88 geometry changed'
    assert before.raw[:36] == after.raw[:36], 'DOS BPB changed'
    name = filename.encode('ascii')
    assert name not in before.entries, 'Destination file already existed'
    assert set(after.entries) == set(before.entries) | {name}, 'Unexpected file entry changes'
    assert after.read(name.decode()) == expected, 'Persisted payload differs'

    cluster, length = after.entries[name]
    chain = []
    max_cluster = 2 + (len(before.raw) - before.data_start) // (before.spc * before.bps)
    while cluster < 0xff8:
        assert 2 <= cluster < max_cluster and cluster not in chain, 'Invalid new cluster chain'
        assert fat_entry(before.fat, cluster) == 0, 'New file reused an allocated cluster'
        chain.append(cluster)
        cluster = fat_entry(after.fat, cluster)
    assert len(chain) == math.ceil(length / (before.spc * before.bps)), 'Unexpected allocation length'

    # Copy only the new file's 12-bit FAT fields, preserving shared nibbles.
    allowed_fat = bytearray(before.fat)
    for cluster in chain:
        offset = cluster * 3 // 2
        word = int.from_bytes(allowed_fat[offset:offset + 2], 'little')
        value = fat_entry(after.fat, cluster)
        word = (word & 0xf) | (value << 4) if cluster & 1 else (word & 0xf000) | value
        allowed_fat[offset:offset + 2] = word.to_bytes(2, 'little')
    unexpected_links = [c for c in range(max_cluster)
                        if fat_entry(allowed_fat, c) != fat_entry(after.fat, c)]
    assert allowed_fat == after.fat, 'Unexpected FAT changes at clusters %s' % unexpected_links[:16]

    bps = before.bps
    reserved = int.from_bytes(before.raw[14:16], 'little')
    fats = before.raw[16]
    roots = int.from_bytes(before.raw[17:19], 'little')
    root_start = reserved * bps + fats * len(before.fat)
    stem, extension = name.split(b'.')
    directory_name = stem.ljust(8, b' ') + extension.ljust(3, b' ')
    matches = [pos for pos in range(root_start, root_start + roots * 32, 32)
               if after.raw[pos:pos + 11] == directory_name]
    assert len(matches) == 1, 'Expected exactly one new directory entry'
    root_pos = matches[0]
    assert before.raw[root_pos] in (0, 0xe5), 'New entry replaced an existing file'

    allowed_ranges = [(root_pos, 32)]
    for n in range(fats):
        offset = reserved * bps + n * len(before.fat)
        assert before.raw[offset:offset + len(before.fat)] == before.fat, 'Input FAT copies differ'
        assert after.raw[offset:offset + len(after.fat)] == after.fat, 'Output FAT copies differ'
        allowed_ranges.append((offset, len(after.fat)))
    for cluster in chain:
        allowed_ranges.append((before.data_start + (cluster - 2) * before.spc * bps,
                               before.spc * bps))

    # Apply the whitelist to physical D88 bytes, retaining all sector headers,
    # track metadata, other file contents, directory entries and free space.
    allowed_image = bytearray(before.data)
    for start, size in allowed_ranges:
        for raw_pos in range(start, start + size):
            sector, within = divmod(raw_pos, bps)
            physical = before.sectors[sector][0] + within
            allowed_image[physical] = after.data[physical]
    assert allowed_image == after.data, 'Image changed outside the new file and its metadata'
    for filename in before.entries:
        assert before.entries[filename] == after.entries[filename], 'Existing directory entry changed'
        assert before.read(filename.decode()) == after.read(filename.decode()), 'Existing file changed'
    print('PASS: %d payload bytes; %d new clusters; matching FAT copies; all unrelated image bytes unchanged' % (len(expected), len(chain)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('--filename', default='Z98WRITE.BIN')
    parser.add_argument('--expected', type=Path, help='Expected contents for a different diagnostic file')
    args = parser.parse_args()
    audit(args.before, args.after, args.filename, args.expected.read_bytes() if args.expected else None)
