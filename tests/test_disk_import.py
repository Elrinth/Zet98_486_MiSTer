"""Synthetic disk fixtures only: no BIOS, DOS or game files required."""
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
from import_disk_image import convert, import_floppy


def payloads(data):
    # Independent D88 reader: verify sector order and actual payload bytes.
    result = []
    for offset in struct.unpack_from('<164I', data, 32):
        if offset:
            count = int.from_bytes(data[offset+4:offset+6], 'little')
            for _ in range(count):
                size = int.from_bytes(data[offset+14:offset+16], 'little')
                result.append((data[offset:offset+4], data[offset+6:offset+9],
                               data[offset+16:offset+16+size]))
                offset += 16+size
    return result


class DiskImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_fdi_payload_chrn_and_original(self):
        source = self.root/'sample.fdi'
        raw = bytes(range(256))*8
        original = struct.pack('<8I', 0, 0x10, 32, 2048, 512, 2, 2, 1)+raw
        source.write_bytes(original)
        output = self.root/'disk.d88'
        convert(source, output)
        records = payloads(output.read_bytes())
        self.assertEqual([x[0] for x in records],
                         [bytes((0,h,r,2)) for h in range(2) for r in (1,2)])
        self.assertEqual(b''.join(x[2] for x in records), raw)
        self.assertEqual(source.read_bytes(), original)
        with self.assertRaises(ValueError): convert(source, output)
        with self.assertRaises(ValueError): convert(source, source)

    def test_hdm_known_and_unknown_geometry(self):
        source = self.root/'sample.hdm'
        source.write_bytes(bytes(range(256))*4928)
        data, info = import_floppy(source)
        self.assertEqual(info['sectors'], 1232)
        self.assertEqual(b''.join(x[2] for x in payloads(data)), source.read_bytes())
        source.write_bytes(b'bad')
        with self.assertRaises(ValueError): import_floppy(source)

    def test_hdi_geometry_and_256_byte_rejection(self):
        source = self.root/'sample.hdi'
        raw = bytes(range(256))*8
        source.write_bytes(struct.pack('<8I',0,0,32,2048,512,2,2,1)+raw)
        output = self.root/'disk.vhd'
        info = convert(source, output)
        self.assertEqual(output.read_bytes(), raw)
        self.assertEqual((info['heads'], info['sectors_per_track']), (2,2))
        source.write_bytes(struct.pack('<8I',0,0,32,2048,256,4,2,1)+raw)
        with self.assertRaisesRegex(ValueError, 'SASI'):
            convert(source, self.root/'sasi.vhd')
        self.assertFalse((self.root/'sasi.vhd').exists())

    def test_nfd_r0_marks_protection_and_truncation(self):
        source = self.root/'sample.nfd'
        header = bytearray(68112)
        header[:15] = b'T98FDDIMAGE.R0\0'
        struct.pack_into('<I',header,272,len(header))
        header[276:278] = bytes((1,2))
        for offset in range(288,288+163*26*16,16): header[offset] = 255
        header[288:299] = bytes((0,0,1,0,0,1,0,0,0,0,0x90))
        raw = bytes(range(128))
        source.write_bytes(header+raw)
        data, info = import_floppy(source)
        self.assertTrue(info['protected'])
        self.assertEqual(data[26], 0x10)
        self.assertEqual(payloads(data), [(bytes((0,0,1,0)), bytes((0x40,0x10,0)), raw)])
        source.write_bytes(header+raw[:-1])
        with self.assertRaises(ValueError): import_floppy(source)
        header[296] = 0x20
        source.write_bytes(header+raw)
        with self.assertRaisesRegex(ValueError, 'protection'): import_floppy(source)
        header[13] = ord('1')
        source.write_bytes(header+raw)
        with self.assertRaisesRegex(ValueError, 'revision 0'): import_floppy(source)


if __name__ == '__main__': unittest.main()
