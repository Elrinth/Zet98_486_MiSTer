#!/usr/bin/env python3
"""Check fixed-loop probe checksums, IF modes, DOS calls and rejection path."""
from pathlib import Path
import struct
import sys
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_CODE
from unicorn.x86_const import *


def run(binary, mode='normal'):
    uc = Uc(UC_ARCH_X86, UC_MODE_16)
    uc.mem_map(0, 2 * 1024 * 1024)
    base = 0x20000
    uc.mem_write(base + 0x100, binary)
    uc.mem_write(base + 2, struct.pack('<H', 0xa000))
    for reg in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
        uc.reg_write(reg, base >> 4)
    uc.reg_write(UC_X86_REG_SP, 0xff00)
    uc.reg_write(UC_X86_REG_EFLAGS, 0x202)
    _, ret_offset, halt_offset = struct.unpack('<HHH', binary[-6:])
    saved, modes, output = [], [], []
    clocks = 0

    def interrupt(machine, number, unused):
        nonlocal clocks
        assert number == 0x21, 'Unexpected interrupt %02x' % number
        ax = uc.reg_read(UC_X86_REG_AX)
        ah = ax >> 8
        pointer = (uc.reg_read(UC_X86_REG_DS) << 4) + uc.reg_read(UC_X86_REG_DX)
        assert uc.reg_read(UC_X86_REG_EFLAGS) & 0x200, 'DOS called with IF clear'
        if ah == 9:
            output.append(bytes(uc.mem_read(pointer, 256)).split(b'$')[0])
        elif ah == 0x2c:
            clocks += 1
            uc.reg_write(UC_X86_REG_CX, 0x0c22)
            uc.reg_write(UC_X86_REG_DX, 0x3807 if clocks <= 17 or mode == 'clock' else 0x3808)
            if mode == 'invalid_clock' and clocks > 17:
                uc.reg_write(UC_X86_REG_DX, 0x3c07)
        elif ah == 0x5b:
            assert bytes(uc.mem_read(pointer, 64)).split(b'\0')[0] == b'A:\\Z98KERN.TXT'
            assert not saved
            uc.reg_write(UC_X86_REG_AX, 0x42)
        elif ah == 0x40:
            assert uc.reg_read(UC_X86_REG_BX) == 0x42
            size = uc.reg_read(UC_X86_REG_CX)
            saved.append(bytes(uc.mem_read(pointer, size)))
            uc.reg_write(UC_X86_REG_AX, size)
        elif ah not in (0x25, 0x3e, 0x0d):
            raise AssertionError('Unexpected DOS function %04x' % ax)
        uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) & ~1)

    def returned(machine, address, size, unused):
        assert uc.reg_read(UC_X86_REG_CS) == 0x9000
        assert uc.reg_read(UC_X86_REG_BX) == uc.reg_read(UC_X86_REG_SI) == 0
        modes.append(bool(uc.reg_read(UC_X86_REG_EFLAGS) & 0x200))
        if mode == 'checksum' and len(modes) == 3:
            uc.reg_write(UC_X86_REG_BX, 1)

    uc.hook_add(UC_HOOK_INTR, interrupt)
    uc.hook_add(UC_HOOK_CODE, returned, begin=0x90000 + ret_offset, end=0x90000 + ret_offset)
    uc.hook_add(UC_HOOK_CODE, lambda *_: uc.emu_stop(),
                begin=base + 0x100 + halt_offset, end=base + 0x100 + halt_offset)
    uc.emu_start(base + 0x100, base + 0x100 + len(binary), count=20000000)
    assert len(saved) == 1, (output, modes)
    if mode == 'checksum':
        assert saved[0] == b'Z98 KERNEL: FAIL stage=1\r\n', saved
        assert modes == [False] * 3 and clocks == 0
    elif mode == 'clock':
        assert saved[0] == b'Z98 KERNEL: FAIL stage=4\r\n', saved
        assert modes == [False] * 8 + [True] * 8 and clocks == 17 + 8 * 65536
    elif mode == 'invalid_clock':
        assert saved[0] == b'Z98 KERNEL: FAIL stage=4\r\n', saved
        assert clocks == 18
    else:
        assert saved[0] == b'Z98 KERNEL: PASS stage=4\r\n', saved
        assert modes == [False] * 8 + [True] * 8 and clocks == 18
    print(('PASS ' + mode + ': ') + saved[0].decode().strip())


if __name__ == '__main__':
    data = Path(sys.argv[1]).read_bytes()
    run(data)
    run(data, 'checksum')
    run(data, 'clock')
    run(data, 'invalid_clock')
