"""Synthetic disk tests; no BIOS, OS or game data required."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
from d88_file import D88
from d88_raw import repack


def fixture():
    raw = bytearray(3 * 512)
    struct.pack_into('<HBHBHHBH', raw, 11, 512, 1, 1, 1, 16, 3, 0xf0, 1)
    data = bytearray(0x2b0)
    struct.pack_into('<I', data, 0x20, len(data))
    for sector in range(3):
        header = bytearray(16)
        struct.pack_into('<4B H', header, 0, 0, 0, sector + 1, 2, 3)
        header[9:14] = b'KEEP!'
        struct.pack_into('<H', header, 14, 512)
        data.extend(header)
        data.extend(raw[sector * 512:(sector + 1) * 512])
    struct.pack_into('<I', data, 0x1c, len(data))
    return data


class RawDiskTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source.d88'
        self.original = fixture()
        self.source.write_bytes(self.original)
        self.disk = D88(self.source)

    def test_roundtrip_and_headers(self):
        self.assertEqual(repack(self.disk, self.disk.raw), self.original)
        raw = bytearray(self.disk.raw)
        raw[514:518] = b'FILE'
        raw[-1] = 0x98
        result = repack(self.disk, raw)
        changed_positions = set()
        cursor = 0
        for pos, size in self.disk.sectors:
            self.assertEqual(result[pos:pos + size], raw[cursor:cursor + size])
            changed_positions.update(range(pos, pos + size))
            cursor += size
        for index in range(len(result)):
            if index not in changed_positions:
                self.assertEqual(result[index], self.original[index])
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_reject_geometry_and_boot_changes(self):
        for raw in (self.disk.raw[:-1], self.disk.raw + b'X', b'X' + self.disk.raw[1:]):
            with self.assertRaises(ValueError):
                repack(self.disk, raw)

    def test_cli_never_overwrites(self):
        raw = self.root / 'disk.raw'
        raw.write_bytes(self.disk.raw)
        output = self.root / 'existing'
        output.write_bytes(b'preserve this')
        for args in (['extract', str(self.source), str(output)],
                     ['repack', str(self.source), str(raw), str(output)]):
            result = subprocess.run([sys.executable, str(SCRIPTS / 'd88_raw.py')] + args,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), b'preserve this')
        self.assertEqual(self.source.read_bytes(), self.original)


if __name__ == '__main__':
    unittest.main()
