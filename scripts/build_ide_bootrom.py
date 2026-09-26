#!/usr/bin/env python3
"""Assemble our PC-98 ATA option ROM and its Quartus word-initialization file."""
import argparse
import hashlib
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--nasm', default='nasm')
parser.add_argument('--output', type=Path, default=root/'build/ide-bootrom')
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
resident = out/'resident.bin'
rom = out/'bootrom.bin'
subprocess.run([args.nasm, '-f', 'bin', 'software/pc98_ide_resident.asm',
                '-o', str(resident), '-l', str(out/'resident.lst')], cwd=root, check=True)
subprocess.run([args.nasm, '-f', 'bin', 'software/pc98_ide_bootrom.asm',
                '-DRESIDENT_BINARY="'+resident.as_posix()+'"',
                '-o', str(rom), '-l', str(out/'bootrom.lst')], cwd=root, check=True)
data = rom.read_bytes()
assert len(data) == 8192 and data[9:12] == bytes.fromhex('55aa10')
text = ''.join(f'{int.from_bytes(data[i:i+2], "little"):04x}\n' for i in range(0,8192,2))
target = root/'rtl/storage/pc98_ide_bootrom.mem'
if args.check:
    assert target.read_text() == text, 'Boot ROM initialization is stale; regenerate it'
else:
    target.write_text(text, encoding='ascii')
print('Boot ROM:', len(data), 'bytes, SHA256', hashlib.sha256(data).hexdigest())
