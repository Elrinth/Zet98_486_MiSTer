#!/usr/bin/env python3
"""Check the private-image bootstrap handoff using Unicorn 2.1.4.

Usage: python tests/ide_bootstrap_preflight.py IDEBOOT.COM private-game.vhd
This executes the loader/ATA reads, not the DOS kernel after IPL handoff.
"""
import argparse
import struct
from pathlib import Path
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_INSN, UC_HOOK_CODE
from unicorn.x86_const import *


def check(binary, image, corrupt=False, vector_segment=0xf800, vector_offset=0x1234, wrapper=False, bootsector=None):
    cpu = Uc(UC_ARCH_X86, UC_MODE_16)
    cpu.mem_map(0, 0x200000)
    cpu.mem_write(0x10100 if bootsector is None else 0x1fc00, binary if bootsector is None else bootsector)
    original_vector = struct.pack('<HH', vector_offset, vector_segment)
    cpu.mem_write(0x1b * 4, original_vector)
    if wrapper:
        cpu.mem_write(vector_segment * 16 + vector_offset,
                      bytes.fromhex('50 24 78 3c 70 58 74 05 ea 82 1a 80 fd'))
    valid_vector = wrapper or 0xe8000 <= vector_segment * 16 + vector_offset < 0x100000
    cpu.reg_write(UC_X86_REG_CS, 0x1000 if bootsector is None else 0x1fc0)
    cpu.mem_write(0x584, b'\x90')
    ports = {}
    state = dict(status=0x50, word=0, data=b'', reads=0, handoff=False)

    def output(cpu, port, size, value, _):
        ports[port] = value
        if port != 0x64e:
            return
        assert size == 1 and value == 0x20, 'Bootstrap must issue only ATA reads'
        lba = ports[0x646] | ports[0x648] << 8 | ports[0x64a] << 16 | (ports[0x64c] & 15) << 24
        state['data'] = image[lba * 512:(lba + 1) * 512]
        if corrupt and lba == 0:
            state['data'] = bytes([state['data'][0] ^ 1]) + state['data'][1:]
        assert len(state['data']) == 512
        state.update(word=0, status=0x58, reads=state['reads'] + 1)

    def input_(cpu, port, size, _):
        if port in (0x74c, 0x64e):
            return state['status']
        if port == 0x640:
            assert size == 2 and state['status'] == 0x58
            value = struct.unpack_from('<H', state['data'], state['word'] * 2)[0]
            state['word'] += 1
            if state['word'] == 256:
                state['status'] = 0x50
            return value
        return ports.get(port, (1 << (size * 8)) - 1)

    def interrupt(cpu, vector, _):
        ax = cpu.reg_read(UC_X86_REG_AX)
        if vector == 0x21:
            if ax == 0x351b:
                cpu.reg_write(UC_X86_REG_BX, vector_offset)
                cpu.reg_write(UC_X86_REG_ES, vector_segment)
            else:
                assert ax >> 8 in (2, 9), hex(ax)
            return
        assert vector == 0x1b
        if bootsector is not None and ax == 0xd690:
            assert state['reads'] == 0
            assert cpu.reg_read(UC_X86_REG_BX) == 4096
            assert cpu.reg_read(UC_X86_REG_CX) == 0x300
            assert cpu.reg_read(UC_X86_REG_DX) == 2
            assert cpu.reg_read(UC_X86_REG_ES) == 0xd800 and cpu.reg_read(UC_X86_REG_BP) == 0x100
            assert len(binary) <= 4096
            cpu.mem_write(0xd8100, binary.ljust(4096, b'\0'))
            cpu.reg_write(UC_X86_REG_EFLAGS, cpu.reg_read(UC_X86_REG_EFLAGS) & ~1)
            return
        flags = cpu.reg_read(UC_X86_REG_EFLAGS)
        cs, ip = cpu.reg_read(UC_X86_REG_CS), cpu.reg_read(UC_X86_REG_IP)
        ss, sp = cpu.reg_read(UC_X86_REG_SS), cpu.reg_read(UC_X86_REG_SP)
        for word in (flags, cs, ip):
            sp = (sp - 2) & 0xffff
            cpu.mem_write(ss * 16 + sp, struct.pack('<H', word & 0xffff))
        cpu.reg_write(UC_X86_REG_SP, sp)
        cpu.reg_write(UC_X86_REG_EFLAGS, flags & ~0x300)
        ip, cs = struct.unpack('<HH', cpu.mem_read(vector * 4, 4))
        cpu.reg_write(UC_X86_REG_CS, cs)
        cpu.reg_write(UC_X86_REG_IP, ip)

    def handoff(cpu, address, size, _):
        if address != 0x1fc00 or state['reads'] < 2:
            return
        assert not corrupt and valid_vector
        assert bytes(cpu.mem_read(0x1fc00, 1024)) == image[:1024]
        assert cpu.mem_read(0x584, 1) == b'\x80'
        assert struct.unpack('<H', cpu.mem_read(0x55c, 2))[0] & 0x100
        assert cpu.reg_read(UC_X86_REG_DS) == 0
        assert cpu.reg_read(UC_X86_REG_SS) == 0xd800
        off, seg = struct.unpack('<HH', cpu.mem_read(0x1b * 4, 4))
        assert seg == 0xd800 and 0x100 <= off < 0x100 + len(binary)
        state['handoff'] = True
        cpu.emu_stop()

    cpu.hook_add(UC_HOOK_INTR, interrupt)
    cpu.hook_add(UC_HOOK_INSN, input_, None, 1, 0, UC_X86_INS_IN)
    cpu.hook_add(UC_HOOK_INSN, output, None, 1, 0, UC_X86_INS_OUT)
    cpu.hook_add(UC_HOOK_CODE, handoff, None, 0x1fc00, 0x1fc00)
    cpu.emu_start(0x10100 if bootsector is None else 0x1fc00, 0x100000, count=1000000)
    expected = not corrupt and valid_vector
    assert state['handoff'] == expected
    assert state['reads'] == (2 if valid_vector else 0)
    if not valid_vector:
        assert bytes(cpu.mem_read(0x1b * 4, 4)) == original_vector
    elif corrupt:
        text = bytes(cpu.mem_read(0xa0000, 112))[::2]
        assert text.startswith(b'Zet98 VHD bootstrap stopped:')
    if expected:
        # Match the real DOS partition IPL's tiny low-memory stack. The old
        # caller-stack bounce buffer clobbered the IVT during this read.
        cpu.mem_write(0x11000, bytes.fromhex('cd 1b f4'))
        cpu.reg_write(UC_X86_REG_CS, 0x1100)
        cpu.reg_write(UC_X86_REG_SS, 0)
        cpu.reg_write(UC_X86_REG_SP, 0x28e)
        cpu.reg_write(UC_X86_REG_AX, 0x0600)
        cpu.reg_write(UC_X86_REG_BX, 512)
        cpu.reg_write(UC_X86_REG_CX, 0)
        cpu.reg_write(UC_X86_REG_DX, 0)
        cpu.reg_write(UC_X86_REG_ES, 0)
        cpu.reg_write(UC_X86_REG_BP, 0x600)
        cpu.reg_write(UC_X86_REG_DS, 0x1234)
        cpu.reg_write(UC_X86_REG_EFLAGS, 0x602)  # IF and DF must survive
        ivt = bytes(cpu.mem_read(0, 512))
        bda = bytes(cpu.mem_read(0x500, 256))
        cpu.emu_start(0x11000, 0x12000, count=1000000)
        assert cpu.reg_read(UC_X86_REG_IP) == 3
        assert bytes(cpu.mem_read(0, 512)) == ivt, 'Tiny boot stack corrupted the IVT'
        assert bytes(cpu.mem_read(0x500, 256)) == bda
        assert bytes(cpu.mem_read(0x600, 512)) == image[:512]
        assert cpu.reg_read(UC_X86_REG_SS) == 0 and cpu.reg_read(UC_X86_REG_SP) == 0x28e
        assert cpu.reg_read(UC_X86_REG_DS) == 0x1234 and cpu.reg_read(UC_X86_REG_BP) == 0x600
        assert cpu.reg_read(UC_X86_REG_EFLAGS) & 0x601 == 0x600
        cpu.reg_write(UC_X86_REG_AX, 0x0600)
        cpu.reg_write(UC_X86_REG_CX, 0xffff)
        cpu.reg_write(UC_X86_REG_DX, 0xff)
        cpu.emu_start(0x11000, 0x12000, count=1000000)
        assert cpu.reg_read(UC_X86_REG_AX) == 0xd000
        assert cpu.reg_read(UC_X86_REG_EFLAGS) & 0x601 == 0x601
        assert bytes(cpu.mem_read(0, 512)) == ivt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('image', type=Path)
    parser.add_argument('--bootsector', type=Path)
    args = parser.parse_args()
    binary = args.binary.read_bytes()
    with args.image.open('rb') as source:
        image = source.read(1024)
    bootsector = args.bootsector.read_bytes() if args.bootsector else None
    check(binary, image, bootsector=bootsector)
    check(binary, image, corrupt=True, bootsector=bootsector)
    check(binary, image, vector_segment=0x2000, bootsector=bootsector)
    check(binary, image, vector_segment=0xe000, vector_offset=0x9234, bootsector=bootsector)
    check(binary, image, vector_segment=0xffff, vector_offset=0xf000, bootsector=bootsector)
    if bootsector is None:
        check(binary, image, vector_segment=0x60, vector_offset=0x7b56, wrapper=True)
    print('PASS: resident BIOS, read-only IPL handoff, tiny boot stack/IVT protection, carry/IF/DF, DOS wrapper, noncanonical ROM pointer, corrupt-image and unsafe-vector rejection')
