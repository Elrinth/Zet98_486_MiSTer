#!/usr/bin/env python3
"""Read a FAT12 file in a D88, or replace it in a new diagnostic copy.

Replacement must fit the existing file length. The source is never written;
FAT entries, the directory entry and D88 metadata remain byte-for-byte intact.
"""
import argparse
from pathlib import Path
import struct


class D88:
    def __init__(self, path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        if len(self.data) < 0x2b0 or struct.unpack_from('<I', self.data, 0x1c)[0] != len(self.data):
            raise ValueError('Expected a single complete D88 image')
        sectors = {}
        for offset in struct.unpack_from('<164I', self.data, 0x20):
            if not offset:
                continue
            count = struct.unpack_from('<H', self.data, offset + 4)[0]
            for _ in range(count):
                c, h, r, n = self.data[offset:offset + 4]
                size = struct.unpack_from('<H', self.data, offset + 14)[0]
                if n > 7 or size != 128 << n or offset + 16 + size > len(self.data):
                    raise ValueError('Unsupported or truncated D88 sector')
                if self.data[offset + 8] or (c, h, r) in sectors:
                    raise ValueError('Sector errors or duplicate sector IDs')
                sectors[c, h, r] = offset + 16, size
                offset += size + 16
        self.sectors = [sectors[key] for key in sorted(sectors)]
        self.raw = b''.join(self.data[pos:pos + size] for pos, size in self.sectors)
        self.bps, self.spc, reserved, fats, roots, total, _, fat_sectors = struct.unpack_from('<HBHBHHBH', self.raw, 11)
        if self.bps not in (128, 256, 512, 1024, 2048) or not self.spc:
            raise ValueError('Unsupported DOS BPB')
        if any(size != self.bps for _, size in self.sectors) or total != len(self.sectors):
            raise ValueError('BPB and D88 geometry differ')
        root_start = (reserved + fats * fat_sectors) * self.bps
        self.data_start = root_start + ((roots * 32 + self.bps - 1) // self.bps) * self.bps
        if (len(self.raw) - self.data_start) // (self.spc * self.bps) >= 4085:
            raise ValueError('Only FAT12 is supported')
        self.fat = self.raw[reserved * self.bps:(reserved + fat_sectors) * self.bps]
        self.entries = {}
        for pos in range(root_start, root_start + roots * 32, 32):
            ent = self.raw[pos:pos + 32]
            if ent[0] == 0:
                break
            if ent[0] == 0xe5 or ent[11] & 0x18:
                continue
            name = ent[:8].rstrip(b' ') + (b'.' + ent[8:11].rstrip(b' ') if ent[8:11].strip() else b'')
            self.entries[name] = struct.unpack_from('<H', ent, 26)[0], struct.unpack_from('<I', ent, 28)[0]

    def positions(self, name):
        cluster, size = self.entries[name.upper().encode('ascii')]
        remaining, seen, positions = size, set(), []
        while remaining:
            if cluster < 2 or cluster >= 0xff0 or cluster in seen:
                raise ValueError('Invalid or short FAT12 chain')
            seen.add(cluster)
            start = self.data_start // self.bps + (cluster - 2) * self.spc
            for sector in range(start, start + self.spc):
                pos, capacity = self.sectors[sector]
                length = min(capacity, remaining)
                positions.extend(range(pos, pos + length))
                remaining -= length
                if not remaining:
                    break
            offset = cluster * 3 // 2
            value = int.from_bytes(self.fat[offset:offset + 2], 'little')
            cluster = (value >> 4) if cluster & 1 else value & 0xfff
        return positions

    def read(self, name):
        return bytes(self.data[pos] for pos in self.positions(name))

    def replace_copy(self, name, replacement, output):
        output = Path(output)
        if output.resolve() == self.path.resolve():
            raise ValueError('Source image must not be overwritten')
        positions = self.positions(name)
        if len(replacement) > len(positions):
            raise ValueError('Replacement exceeds existing file size')
        result = bytearray(self.data)
        for pos, byte in zip(positions, replacement.ljust(len(positions), b'\0')):
            result[pos] = byte
        # Exclusive creation also prevents overwriting another test result.
        with output.open('xb') as stream:
            stream.write(result)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('filename')
    parser.add_argument('output', type=Path)
    parser.add_argument('--replace', type=Path)
    args = parser.parse_args()
    disk = D88(args.image)
    if args.replace:
        disk.replace_copy(args.filename, args.replace.read_bytes(), args.output)
    else:
        content = disk.read(args.filename)
        with args.output.open('xb') as stream:
            stream.write(content)
