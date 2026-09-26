#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run a z486_fuzz_gen.py program on Unicorn and compare with the z486 dump.

Usage: z486_fuzz_compare.py <fuzz-N.bin> <fuzz-N.z486> <fuzz-N.json>
Reports the first block whose logged GPRs differ and its instructions.
"""
import json
import sys
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_INSN
from unicorn.x86_const import UC_X86_INS_OUT, UC_X86_REG_EIP

LOG = 0x50000
REGS = ['eax', 'ebx', 'ecx', 'edx', 'esi', 'edi', 'ebp', 'esp']
binary = open(sys.argv[1], 'rb').read()
z486 = open(sys.argv[2], 'rb').read()
manifest = json.load(open(sys.argv[3]))
far = binary.find(bytes([0x66, 0xea]))
pm32 = int.from_bytes(binary[far + 2:far + 6], 'little')
mu = Uc(UC_ARCH_X86, UC_MODE_32)
mu.mem_map(0, 0x100000)
mu.mem_map(0x2000000, 0x100000)
mu.mem_write(0x10100, binary)
done = []
def out(uc, port, size, value, user):
    if port == 0x7ff0:
        done.append(value)
        uc.emu_stop()
mu.hook_add(UC_HOOK_INSN, out, None, 1, 0, UC_X86_INS_OUT)
# Skip the selector loads (flat segments in Unicorn): mov ax,10h / mov ds,es,ss.
assert binary[pm32 - 0x100:pm32 - 0x100 + 10].hex() == '66b810008ed88ec08ed0'
mu.emu_start(0x10000 + pm32 + 10, 0, count=50_000_000)
assert done == [0x600d], ('reference did not finish', done, hex(mu.reg_read(UC_X86_REG_EIP)))
ref = bytes(mu.mem_read(0x40000, 0x60000))
if len(z486) != len(ref):
    sys.exit(f'FAIL: dump size {len(z486)} != {len(ref)}')
for i, body in enumerate(manifest):
    at = LOG - 0x40000 + i * 32
    a, b = z486[at:at + 32], ref[at:at + 32]
    if a != b:
        print(f'FAIL: first mismatch after block {i}')
        for n, reg in enumerate(REGS):
            x = int.from_bytes(a[n * 4:n * 4 + 4], 'little')
            y = int.from_bytes(b[n * 4:n * 4 + 4], 'little')
            print(f'  {reg}: z486={x:08x} ref={y:08x}{"  <--" if x != y else ""}')
        start = max(0, i - 1)
        for j in range(start, i + 1):
            print(f'  block {j}:')
            for line in manifest[j]:
                print('    ' + line)
        sys.exit(1)
if z486 != ref:
    first = next(k for k in range(len(ref)) if z486[k] != ref[k])
    sys.exit(f'FAIL: registers match but memory differs first at {0x40000 + first:#x}')
print(f'PASS: {len(manifest)} blocks, registers and 384 KB of RAM match Unicorn')
