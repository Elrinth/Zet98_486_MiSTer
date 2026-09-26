#!/usr/bin/env python3
"""Validate the DOS probe's capture layout against a simple banked VRAM model."""
import json
import sys
from pathlib import Path
from unicorn import (Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INSN,
                     UC_HOOK_INTR, UC_HOOK_MEM_READ, UC_HOOK_MEM_WRITE)
from unicorn.x86_const import *

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_grcg_bulk_probe import verify

u = Uc(UC_ARCH_X86, UC_MODE_16)
u.mem_map(0, 0x200000)
u.mem_write(0x10100, Path(sys.argv[1]).read_bytes())
u.mem_write(0x10002, b'\x00\x90')
for register in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
    u.reg_write(register, 0x1000)
u.reg_write(UC_X86_REG_IP, 0x100)
planes = [[bytearray(32768) for _ in range(4)] for _ in range(2)]
state = dict(page=0, mode=0, tile_index=0, tiles=[0]*4, done=False)
capture = bytearray()
bases = [0xa8000, 0xb0000, 0xb8000, 0xe0000]


def io_out(uc, port, size, value, _):
    if port == 0xa6:
        state['page'] = value & 1
    elif port == 0x7c:
        state['mode'] = value
        state['tile_index'] = 0
    elif port == 0x7e:
        state['tiles'][state['tile_index']] = value & 255
        state['tile_index'] = (state['tile_index'] + 1) & 3


def memory(uc, access, address, size, value, plane):
    offset = address - bases[plane]
    assert 0 <= offset <= 32768-size
    page = planes[state['page']]
    if access == 16:  # UC_MEM_READ
        uc.mem_write(address, bytes(page[plane][offset:offset+size]))
    else:
        for byte in range(size):
            mask = (value >> (byte*8)) & 255
            if state['mode'] & 0x80:
                assert state['mode'] == 0xc0
                for target in range(4):
                    previous = page[target][offset+byte]
                    page[target][offset+byte] = ((previous & (mask ^ 255)) |
                                                 (state['tiles'][target] & mask))
            else:
                page[plane][offset+byte] = mask


def interrupt(uc, number, _):
    assert number == 0x21
    ax = uc.reg_read(UC_X86_REG_AX)
    ah = ax >> 8
    if ah == 0x5b:
        uc.reg_write(UC_X86_REG_AX, 5)
    elif ah == 0x40:
        length = uc.reg_read(UC_X86_REG_CX)
        address = uc.reg_read(UC_X86_REG_DS)*16 + uc.reg_read(UC_X86_REG_DX)
        capture.extend(uc.mem_read(address, length))
        uc.reg_write(UC_X86_REG_AX, length)
    elif ah == 9:
        address = uc.reg_read(UC_X86_REG_DS)*16 + uc.reg_read(UC_X86_REG_DX)
        message = bytes(uc.mem_read(address, 64)).split(b'$')[0]
        assert b'capture saved' in message, message
        state['done'] = True
        uc.emu_stop()
    else:
        assert ah in (0x25, 0x3e, 0x0d), hex(ax)
    uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) & ~1)


u.hook_add(UC_HOOK_INSN, io_out, None, 1, 0, UC_X86_INS_OUT)
u.hook_add(UC_HOOK_INSN, lambda uc, port, size, _: state['page'], None, 1, 0, UC_X86_INS_IN)
u.hook_add(UC_HOOK_INTR, interrupt)
for plane, base in enumerate(bases):
    u.hook_add(UC_HOOK_MEM_READ | UC_HOOK_MEM_WRITE, memory, plane, base, base+32767)
u.emu_start(0x10100, 0, count=30000000)
assert state['done'], 'Probe did not finish within the instruction bound'
result = verify(capture)
assert result['passed'], result
capture[24] ^= 1
assert not verify(capture)['passed'], 'Verifier missed an injected byte corruption'
print(json.dumps(dict(reference=result, negative_control='PASS'), indent=2))
