#!/usr/bin/env python3
"""Check integer vectors and failure reporting against an independent emulator."""
from pathlib import Path
import struct
import sys
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_CODE
from unicorn.x86_const import *


def run(binary, corrupt=None):
    uc = Uc(UC_ARCH_X86, UC_MODE_16)
    uc.mem_map(0, 2*1024*1024)
    base = 0x20000
    uc.mem_write(base+0x100, binary)
    for register in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
        uc.reg_write(register, base >> 4)
    uc.reg_write(UC_X86_REG_SP, 0xff00)
    uc.reg_write(UC_X86_REG_EFLAGS, 0x202)
    after_mul, after_sub, park = struct.unpack('<HHH', binary[-6:])
    saved = []
    output = []
    injected = False

    def interrupt(machine, number, unused):
        assert number == 0x21, 'Unexpected interrupt %02x' % number
        ax = uc.reg_read(UC_X86_REG_AX)
        ah = ax >> 8
        pointer = (uc.reg_read(UC_X86_REG_DS) << 4)+uc.reg_read(UC_X86_REG_DX)
        if ah == 0x25:
            uc.mem_write((ax & 255)*4, struct.pack('<HH', uc.reg_read(UC_X86_REG_DX), uc.reg_read(UC_X86_REG_DS)))
        elif ah == 9:
            output.append(bytes(uc.mem_read(pointer, 512)).split(b'$')[0])
        elif ah == 0x5b:
            assert bytes(uc.mem_read(pointer, 64)).split(b'\0')[0] == b'A:\\Z98INT.TXT'
            assert not saved
            uc.reg_write(UC_X86_REG_AX, 0x42)
        elif ah == 0x40:
            assert uc.reg_read(UC_X86_REG_BX) == 0x42
            length = uc.reg_read(UC_X86_REG_CX)
            saved.append(bytes(uc.mem_read(pointer, length)))
            uc.reg_write(UC_X86_REG_AX, length)
        elif ah not in (0x3e, 0x0d):
            raise AssertionError('Unexpected DOS function %04x' % ax)
        uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) & ~1)

    def inject(machine, address, size, unused):
        nonlocal injected
        if corrupt == 'multiply':
            uc.reg_write(UC_X86_REG_AX, uc.reg_read(UC_X86_REG_AX) ^ 1)
            injected = True

    def inject_borrow(machine, address, size, unused):
        nonlocal injected
        if corrupt == 'borrow' and not injected:
            uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) ^ 1)
            injected = True

    def stop(machine, address, size, unused):
        uc.emu_stop()

    uc.hook_add(UC_HOOK_INTR, interrupt)
    uc.hook_add(UC_HOOK_CODE, inject, begin=base+0x100+after_mul, end=base+0x100+after_mul)
    uc.hook_add(UC_HOOK_CODE, inject_borrow, begin=base+0x100+after_sub, end=base+0x100+after_sub)
    uc.hook_add(UC_HOOK_CODE, stop, begin=base+0x100+park, end=base+0x100+park)
    uc.emu_start(base+0x100, base+0x100+len(binary), count=100000)
    expected = {'multiply': b'FAIL stage=1', 'borrow': b'FAIL stage=6', None: b'PASS stage=6'}[corrupt]
    assert len(saved) == 1 and expected in saved[0], (output, saved)
    assert injected == bool(corrupt)
    print(('PASS injected-error rejection: ' if corrupt else 'PASS emulator: ')+saved[0].decode().strip())


if __name__ == '__main__':
    payload = Path(sys.argv[1]).read_bytes()
    run(payload)
    run(payload, 'multiply')
    run(payload, 'borrow')
