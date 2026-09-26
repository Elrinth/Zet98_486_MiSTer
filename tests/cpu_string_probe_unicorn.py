#!/usr/bin/env python3
"""Check REP string vectors and failure reporting against an independent emulator."""
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
    after_stos, after_scas, park = struct.unpack('<HHH', binary[-6:])
    uc.mem_write(base+2, b'\x00\x90')
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
            assert bytes(uc.mem_read(pointer, 64)).split(b'\0')[0] == b'A:\\Z98STR.TXT'
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
        if corrupt == 'carry':
            uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) ^ 1)
            injected = True

    def inject_zero(machine, address, size, unused):
        nonlocal injected
        if corrupt == 'zero' and not injected:
            uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) ^ 0x40)
            injected = True

    def stop(machine, address, size, unused):
        uc.emu_stop()

    uc.hook_add(UC_HOOK_INTR, interrupt)
    uc.hook_add(UC_HOOK_CODE, inject, begin=base+0x100+after_stos, end=base+0x100+after_stos)
    uc.hook_add(UC_HOOK_CODE, inject_zero, begin=base+0x100+after_scas, end=base+0x100+after_scas)
    uc.hook_add(UC_HOOK_CODE, stop, begin=base+0x100+park, end=base+0x100+park)
    uc.emu_start(base+0x100, base+0x100+len(binary), count=200000)
    expected = {'carry': b'FAIL stage=01', 'zero': b'FAIL stage=03', None: b'PASS stage=25'}[corrupt]
    assert len(saved) == 1 and expected in saved[0], (output, saved)
    assert injected == bool(corrupt)
    print(('PASS injected-error rejection: ' if corrupt else 'PASS emulator: ')+saved[0].decode().strip())


if __name__ == '__main__':
    payload = Path(sys.argv[1]).read_bytes()
    run(payload)
    run(payload, 'carry')
    run(payload, 'zero')
