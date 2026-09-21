#!/usr/bin/env python
# SPDX-License-Identifier: GPL-3.0-or-later
"""Independent FAT16 check of hdd_file_probe.asm; Python 2.7/3 compatible."""
from __future__ import print_function
import argparse
import gzip
import hashlib
import json
import os
import struct

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('image')
parser.add_argument('--baseline-gzip', help='Check every other image sector against the pristine staging archive')
parser.add_argument('--extract', help='Write the verified diagnostic payload to a new file')
parser.add_argument('--metadata-only', action='store_true', help='With a baseline, audit its first MiB and the complete diagnostic file')
args = parser.parse_args()
if args.metadata_only and not args.baseline_gzip:
    parser.error('--metadata-only requires --baseline-gzip')
base = 69632
with open(args.image, 'rb') as disk:
    disk.seek(base)
    boot = disk.read(512)
    bps, spc, reserved, fats, roots, total, media, fat_size = struct.unpack_from('<HBHBHHBH', boot, 11)
    assert (bps, spc, fats, roots) == (512, 32, 2, 3072), 'Unexpected private test-volume geometry'
    fat_start = base + reserved * bps
    disk.seek(fat_start)
    fat = disk.read(fat_size * bps)
    assert len(fat) == fat_size * bps and fat == disk.read(len(fat)), 'FAT copies differ'
    root_start = fat_start + fats * len(fat)
    data_start = root_start + roots * 32
    disk.seek(root_start)
    directory = disk.read(roots * 32)
    entries = [directory[i:i + 32] for i in range(0, len(directory), 32)
               if directory[i:i + 11] == b'Z98WRITEBIN']
    assert len(entries) == 1, 'Expected exactly one Z98WRITE.BIN directory entry'
    entry = entries[0]
    assert not (entry[11] if isinstance(entry[11], int) else ord(entry[11])) & 0x18
    cluster, size = struct.unpack_from('<HI', entry, 26)
    assert size == 70001, 'Unexpected diagnostic file size'
    clusters, payload = [], bytearray()
    while cluster < 0xfff8:
        assert cluster >= 2 and cluster not in clusters and cluster * 2 + 2 <= len(fat), 'Invalid FAT chain'
        clusters.append(cluster)
        disk.seek(data_start + (cluster - 2) * spc * bps)
        payload.extend(disk.read(spc * bps))
        cluster = struct.unpack_from('<H', fat, cluster * 2)[0]
    assert len(clusters) == (size + spc * bps - 1) // (spc * bps)
    payload = bytes(payload[:size])
    expected = bytes(bytearray(((i // 1024) + (i % 1024) * 37) & 255 for i in range(size)))
    assert payload == expected, 'Persisted diagnostic bytes differ'
    result = dict(result='PASS', size=size, clusters=clusters,
                  sha256=hashlib.sha256(payload).hexdigest(), fat_copies_equal=True)
    if args.baseline_gzip:
        allowed = set(range(fat_start // bps, data_start // bps))
        for c in clusters:
            first = data_start // bps + (c - 2) * spc
            allowed.update(range(first, first + spc))
        disk.seek(0)
        changed, position = [], 0
        with gzip.open(args.baseline_gzip, 'rb') as baseline:
            while True:
                original = baseline.read(1024 * 1024)
                current = disk.read(len(original))
                assert len(original) == len(current), 'Image length changed'
                if not original:
                    assert disk.read(1) == b'', 'Image grew'
                    break
                if position == 0:
                    assert data_start <= len(original), 'Metadata exceeds the first comparison block'
                    old_fat = original[fat_start:fat_start + len(fat)]
                    for c in clusters:
                        assert struct.unpack_from('<H', old_fat, c * 2)[0] == 0, 'File reused an allocated cluster'
                    for c in range(len(fat) // 2):
                        if c not in clusters:
                            assert old_fat[c * 2:c * 2 + 2] == fat[c * 2:c * 2 + 2], 'Unrelated FAT entry changed'
                    old_root = original[root_start:data_start]
                    for offset in range(0, len(directory), 32):
                        old_entry, new_entry = old_root[offset:offset + 32], directory[offset:offset + 32]
                        if old_entry != new_entry:
                            assert old_entry[:1] in (b'\0', b'\xe5') and new_entry == entry, 'Unrelated directory entry changed'
                    result.update(other_fat_entries_unchanged=True, other_root_entries_unchanged=True)
                if original != current:
                    for offset in range(0, len(original), bps):
                        if original[offset:offset + bps] != current[offset:offset + bps]:
                            sector = (position + offset) // bps
                            assert sector in allowed, 'Unexpected image write at sector {}'.format(sector)
                            changed.append(sector)
                position += len(original)
                if args.metadata_only:
                    break
        assert changed, 'Expected persisted file allocation/data changes'
        result.update(compared_image_bytes=position, changed_sectors=len(changed),
                      only_fat_root_and_test_clusters_changed=True, metadata_only=args.metadata_only)
if args.extract:
    fd = os.open(args.extract, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as target:
        target.write(payload)
print(json.dumps(result, sort_keys=True))
