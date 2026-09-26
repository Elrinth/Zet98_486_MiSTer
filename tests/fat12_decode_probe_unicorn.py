#!/usr/bin/env python3
"""Validate the synthetic FAT table and independent failure injection."""
from pathlib import Path
import struct
import sys
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_CODE, UC_HOOK_INSN
from unicorn.x86_const import *


def run(binary, corrupt=None):
    decoded, park, table = struct.unpack('<HHH', binary[-6:])
    fat = binary[table:table + 1800]
    for index in range(2, 1200):
        word = int.from_bytes(fat[index * 3 // 2:index * 3 // 2 + 2], 'little')
        value = (word >> 4) if index & 1 else (word & 4095)
        expected = index + 1 if index < 1089 else 4095 if index == 1089 else 0
        assert value == expected
    uc = Uc(UC_ARCH_X86, UC_MODE_16)
    uc.mem_map(0, 2 * 1024 * 1024)
    base = 0x20000
    uc.mem_write(base + 0x100, binary)
    for reg in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_SS):
        uc.reg_write(reg, base >> 4)
    output = []
    ports = []
    injected = False

    def interrupt(machine, number, unused):
        assert number == 0x21 and uc.reg_read(UC_X86_REG_AH) == 9
        pointer = (uc.reg_read(UC_X86_REG_DS) << 4) + uc.reg_read(UC_X86_REG_DX)
        output.append(bytes(uc.mem_read(pointer, 200)).split(b'$')[0])

    def inject(machine, address, size, unused):
        nonlocal injected
        if corrupt is not None and uc.reg_read(UC_X86_REG_BX) == corrupt and not injected:
            uc.reg_write(UC_X86_REG_AX, 0 if corrupt < 1090 else 1)
            injected = True

    uc.hook_add(UC_HOOK_INTR, interrupt)
    uc.hook_add(UC_HOOK_INSN,
                lambda machine, port, size, value, unused: ports.append((port, size, value)),
                None, 1, 0, UC_X86_INS_OUT)
    uc.hook_add(UC_HOOK_CODE, inject, begin=base + 0x100 + decoded,
                end=base + 0x100 + decoded)
    uc.hook_add(UC_HOOK_CODE, lambda *args: uc.emu_stop(),
                begin=base + 0x100 + park, end=base + 0x100 + park)
    uc.emu_start(base + 0x100, base + 0x100 + len(binary), count=2000000)
    assert len(output) == 1 and output[0].startswith(b'PASS' if corrupt is None else b'FAIL')
    assert injected == (corrupt is not None)
    assert not ports if corrupt is None else ports[-1] == (0x7ff0, 2, corrupt)
    print('PASS independent probe validation:', corrupt, output[0].decode().strip())


if __name__ == '__main__':
    binary = Path(sys.argv[1]).read_bytes()
    for corrupt in (None, 69, 101, 289, 377, 1090):
        run(binary, corrupt)
