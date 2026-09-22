import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('probe', Path(__file__).resolve().parents[1]/
                                             'scripts/verify_grcg_alias_probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class CaptureChecks(unittest.TestCase):
    def capture(self):
        return bytearray(b'Z98GAL1\0'+struct.pack('<H',512)+bytes(6)+
                         b''.join(header+data for header,data in probe.records()))

    def test_known_pixels_and_guards(self):
        header, pixels = next(probe.records())
        self.assertEqual(header, bytes(4))
        # B initially: 03 4c 95 de 27 70 b9 02; write mask5a/a5 at2/3.
        self.assertEqual(pixels[:8], bytes.fromhex('034c9d7e2770b902'))
        records = list(probe.records())
        for header, pixels in records:
            if header[1] == 15:
                self.assertEqual(pixels, bytes((i*73+p*61+header[0]*29+3)%256
                                                for p in range(4) for i in range(8)))

    def test_each_alias_and_guard_corruption_fails(self):
        original = self.capture()
        self.assertEqual(probe.inspect(original)['mismatching_bytes'], 0)
        for alias in range(4):
            for offset in (0, 2, 3, 4, 7, 31):
                bad = original.copy()
                bad[16+36*(alias*4)+4+offset] ^= 1
                report = probe.inspect(bad)
                self.assertEqual(report['mismatching_bytes'], 1)
                self.assertEqual(report['mismatching_records_by_alias'][alias], 1)

    def test_truncated_reordered_or_wrong_capture_rejected(self):
        original = self.capture()
        bad = [original[:-1], original+bytes(1)]
        for offset in (0, 8, 10, 16, 17, 18, 19):
            changed = original.copy()
            changed[offset] ^= 1
            bad.append(changed)
        for data in bad:
            with self.assertRaises(ValueError):
                probe.inspect(data)


if __name__ == '__main__':
    unittest.main()
