"""Golden arithmetic and malformed/corrupted capture checks for the verifier."""
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_glyph_expand_probe import inspect


def capture():
    # Separate bit-position arithmetic oracle; the verifier uses pixel strings.
    lookup = [sum(((value >> bit) & 1) * (3 << (2*bit))
                  for bit in range(8)) for value in range(256)]
    expanded = b''.join(struct.pack('>HH', lookup[i], lookup[i ^ 0xa5])
                        for i in range(256))
    shifted = b''.join(struct.pack('>HH', ((lookup[i] << 1) & 0xffff) |
                                  (lookup[i ^ 0xa5] >> 15),
                                  (lookup[i ^ 0xa5] << 1) & 0xffff)
                       for i in range(256))
    data = bytearray(b'Z98GLYF1' + struct.pack('<HHBBH', 0x120e, 0xa000, 8, 10, 2))
    for segment in (0x7000, 0x9000):
        data += struct.pack('<H', segment) + expanded + shifted
    return data


class GlyphCaptureTests(unittest.TestCase):
    def test_golden(self):
        result = inspect(capture())
        self.assertEqual(result['mismatches'], 0)
        self.assertEqual(len(result['checks']), 4)
        self.assertEqual(sum(c['bytes'] for c in result['checks']), 4096)

    def test_corruption_in_every_region(self):
        for base in (18, 1042, 2068, 3092):
            for offset in (0, 255, 511, 1023):
                with self.subTest(base=base, offset=offset):
                    data = capture()
                    data[base + offset] ^= 1
                    self.assertEqual(inspect(data)['mismatches'], 1)

    def test_wrong_endianness(self):
        data = capture()
        for base in (18, 2068):
            for offset in range(base, base + 2048, 2):
                data[offset], data[offset+1] = data[offset+1], data[offset]
        self.assertGreater(inspect(data)['mismatches'], 0)

    def test_malformed_capture(self):
        for at, payload in ((0, b'X'), (8, struct.pack('<H', 0x6001)),
                            (10, struct.pack('<H', 0x92ff)), (14, b'\x03'),
                            (16, b'\x01'), (2066, b'\x01')):
            with self.subTest(at=at):
                data = capture()
                data[at:at+len(payload)] = payload
                with self.assertRaises(ValueError):
                    inspect(data)
        for data in (capture()[:-1], capture() + b'\0'):
            with self.assertRaises(ValueError):
                inspect(data)


if __name__ == '__main__':
    unittest.main()
