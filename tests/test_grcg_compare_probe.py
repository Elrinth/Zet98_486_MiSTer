import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('probe', Path(__file__).resolve().parents[1]/
                                              'scripts/verify_grcg_compare_probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class CaptureChecks(unittest.TestCase):
    def capture(self):
        return bytearray(b'Z98GCMP1'+struct.pack('<H',2048)+bytes(6)+
                         b''.join(header+data for header,data in probe.records()))

    def test_known_pixel_colors(self):
        # At byte zero/page zero, the four planes hold 03,40,7d,ba.
        # Their equality masks against 3c,a5,5a,c3 are c0,1a,d8,86.
        for disabled, expected in ((14,0xc0),(13,0x1a),(11,0xd8),(7,0x86),(0,0),(15,0xff)):
            self.assertEqual(probe.pixel_byte(0,disabled,0),expected)

    def test_result_corruption_is_failure(self):
        capture=self.capture()
        self.assertEqual(probe.inspect(capture)['mismatching_records'],0)
        # Last record has every plane disabled and must return all ones.
        capture[-1]=0
        report=probe.inspect(capture)
        self.assertEqual(report['mismatching_records'],1)
        self.assertEqual(report['first_mismatches'][0]['expected'],'ffffffffffff')

    def test_incomplete_and_misidentified_captures_rejected(self):
        original=self.capture()
        bad=[original[:-1],original+bytes(1)]
        for at in (0,8,10,16,17,18,19):
            modified=original.copy(); modified[at]^=1; bad.append(modified)
        for data in bad:
            with self.assertRaises(ValueError):
                probe.inspect(data)


if __name__=='__main__':
    unittest.main()
