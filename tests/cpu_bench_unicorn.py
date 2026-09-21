#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check the DOS benchmark's checksums/logging, not FPGA performance.

Requires Unicorn 2.1.4 and a NASM-assembled cpu_bench.asm binary. The DOS
clock advances on queries, including an hour wrap. A corrupted POP must fail.
"""
from pathlib import Path
import sys
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR
from unicorn.x86_const import *


def run(binary, negative=False):
    u = Uc(UC_ARCH_X86, UC_MODE_16)
    u.mem_map(0, 0x200000)
    u.mem_write(0x10100, binary)
    u.reg_write(UC_X86_REG_CS, 0x1000)
    state = dict(time=359800, output=bytearray(), saved=bytearray(), writes=0)

    def dos(uc, vector, _):
        assert vector == 0x21, hex(vector)
        ax, dx = uc.reg_read(UC_X86_REG_AX), uc.reg_read(UC_X86_REG_DX)
        ds = uc.reg_read(UC_X86_REG_DS)
        ah = ax >> 8
        uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) & ~1)
        if ah == 0x25:
            pass
        elif ah == 0x2c:
            state['time'] += 100
            t = state['time'] % 360000
            uc.reg_write(UC_X86_REG_CX, (t // 6000) % 60)
            uc.reg_write(UC_X86_REG_DX, ((t // 100) % 60) << 8 | (t % 100))
        elif ah == 2:
            state['output'].append(dx & 255)
        elif ah == 0x3c:
            uc.reg_write(UC_X86_REG_AX, 5)
        elif ah == 0x40:
            size = uc.reg_read(UC_X86_REG_CX)
            state['saved'].extend(uc.mem_read(ds * 16 + dx, size))
            state['writes'] += 1
            uc.reg_write(UC_X86_REG_AX, size)
        else:
            assert ah in (0x3e, 0x0d), hex(ax)

    u.hook_add(UC_HOOK_INTR, dos)
    u.emu_start(0x10100, 0x200000, count=100_000_000)
    output = bytes(state['output'])
    assert state['writes'] == 1 and bytes(state['saved']) in output
    assert b'Saved Z98PERF.TXT. Benchmark finished.' in output, output
    for title in (b'ALU blocks=10 elapsed=1000', b'RAM copy blocks=10 elapsed=1000'):
        assert title in output, output
    if negative:
        assert b'FAIL: kernel checksum.' in output and b'PASS:' not in output, output
    else:
        assert b'Stack blocks=10 elapsed=1000' in output, output
        assert b'PASS: ALU, RAM and stack checksums.' in output, output


binary = Path(sys.argv[1]).read_bytes()
assert len(binary) <= 2011
run(binary)
pattern = b'\x53\x5f\x39\xdf'  # push bx; pop di; cmp di,bx
assert binary.count(pattern) == 1
run(binary.replace(pattern, b'\x53\x58\x39\xdf'), negative=True)
print('PASS benchmark v3: all checksums, hour wrap, exact saved log; wrong POP rejected')
