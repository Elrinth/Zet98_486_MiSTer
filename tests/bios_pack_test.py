#!/usr/bin/env python3
"""ROM-free tests for the user ROM layout converter."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('bios_pack', Path(__file__).resolve().parents[1]/'scripts/pc98_pack_bios.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PackTest(unittest.TestCase):
    def test_layout_and_optional_sound(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = {n: bytes([i+1])*size for i, (n, size) in enumerate(module.SIZES.items())}
            for name, content in data.items():
                (root/name.upper()).write_bytes(content)
            packed = module.pack(root)
            self.assertEqual(len(packed), 550912)
            for name, content in data.items():
                offset = module.OFFSETS[name]
                self.assertEqual(packed[offset:offset+len(content)], content)
            self.assertEqual(packed[0x24000:0x40000], bytes(0x1c000))
            (root/'SOUND.ROM').unlink()
            self.assertEqual(module.pack(root)[0x20000:0x40000], bytes(0x20000))
            with zipfile.ZipFile(root/'input.zip', 'w') as z:
                for name, content in data.items():
                    z.writestr('folder/'+name, content)
            self.assertEqual(module.pack(root/'input.zip'), packed)

    def test_missing_size_and_duplicate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(ValueError, 'Missing'):
                module.pack(root)
            (root/'bios.rom').write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError, 'expected'):
                module.pack(root)
            with zipfile.ZipFile(root/'input.zip', 'w') as z:
                z.writestr('one/bios.rom', bytes(0x18000))
                z.writestr('two/BIOS.ROM', bytes(0x18000))
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                module.pack(root/'input.zip')


if __name__ == '__main__':
    unittest.main()
