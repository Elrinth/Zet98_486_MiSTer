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


def run(binary, negative=False, save_fault=None):
    u = Uc(UC_ARCH_X86, UC_MODE_16)
    u.mem_map(0, 0x200000)
    u.mem_write(0x10100, binary)
    # End of the DOS allocation, used by the optional 90000h kernel guard.
    u.mem_write(0x10002, b'\x00\xa0')
    u.mem_write(0x10018, bytes(range(5)) + bytes([255]) * 15)
    u.mem_write(0x10032, bytes.fromhex('14 00 18 00 00 10'))
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
        elif ah == 0x51:
            uc.reg_write(UC_X86_REG_BX, 0x1000)
        elif ah == 0x2c:
            state['time'] += 100
            t = state['time'] % 360000
            uc.reg_write(UC_X86_REG_CX, (t // 6000) % 60)
            uc.reg_write(UC_X86_REG_DX, ((t // 100) % 60) << 8 | (t % 100))
        elif ah == 2:
            state['output'].append(dx & 255)
        elif ah == 0x3c:
            if save_fault == 'create':
                uc.reg_write(UC_X86_REG_AX, 5)
                uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) | 1)
                return
            uc.reg_write(UC_X86_REG_AX, 5)
            uc.mem_write(0x1001d, b'\x07')  # deliberately not the handle number
        elif ah == 0x40:
            if save_fault == 'write':
                uc.reg_write(UC_X86_REG_AX, 29)
                uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) | 1)
                return
            size = uc.reg_read(UC_X86_REG_CX)
            state['saved'].extend(uc.mem_read(ds * 16 + dx, size))
            state['writes'] += 1
            uc.reg_write(UC_X86_REG_AX, size if save_fault != 'short' else 0)
        else:
            assert ah in (0x3e, 0x0d), hex(ax)
            if ah == 0x3e and save_fault == 'close':
                uc.reg_write(UC_X86_REG_AX, 6)
                uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) | 1)

    u.hook_add(UC_HOOK_INTR, dos)
    u.emu_start(0x10100, 0x200000, count=100_000_000)
    output = bytes(state['output'])
    if save_fault:
        stage, error = {'create': (1, 5), 'write': (2, 29),
                        'short': (2, 0), 'close': (3, 6)}[save_fault]
        expected = 'ERROR saving Z98PERF.TXT. Stage={} AX={} INT24 DI=65535'.format(stage, error).encode()
        assert expected in output and b'Saved Z98PERF' not in output, output
        if save_fault != 'create':
            assert b' BX=5' in output, output
            assert b' CS=4096 DS=4096 PSP=4096 JFT=0 1 2 3 4 7 ' in output, output
            assert b' COUNT=20 PTR=4096:24' in output, output
        return
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
for fault in ('create', 'write', 'short', 'close'):
    run(binary, save_fault=fault)
print('PASS benchmark v3: checksums, hour wrap, saved log, wrong POP, and DOS save error stages')
