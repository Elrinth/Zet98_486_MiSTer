#!/usr/bin/env python3
"""Check the DOS probe's API sequence and success/failure handling."""
import json
from pathlib import Path
import struct
import sys

sys.path.insert(0, 'build/verification-python')
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_CODE
from unicorn.x86_const import *


def run(program, reject_resize=False, corrupt_copy=False, copy_only=False):
    u = Uc(UC_ARCH_X86, UC_MODE_16)
    u.mem_map(0, 0x100000)
    u.mem_write(0x20100, program)
    u.mem_write(0x40000, b'\xcb')  # XMS entry returns with RETF.
    for reg, value in [(UC_X86_REG_CS, 0x2000), (UC_X86_REG_DS, 0x2000),
                       (UC_X86_REG_ES, 0x2000), (UC_X86_REG_SS, 0x2000),
                       (UC_X86_REG_SP, 0xfffe), (UC_X86_REG_EFLAGS, 0x202)]:
        u.reg_write(reg, value)
    output, calls, sizes = [], [], []
    blocks, locked, parked = {}, set(), []

    def intr(uc, number, _):
        ax = uc.reg_read(UC_X86_REG_AX)
        if number == 0x2f:
            if ax == 0x4300:
                uc.reg_write(UC_X86_REG_AL, 0x80)
            else:
                assert ax == 0x4310
                uc.reg_write(UC_X86_REG_ES, 0x4000)
                uc.reg_write(UC_X86_REG_BX, 0)
        else:
            assert number == 0x21
            if ax >> 8 == 9:
                address = uc.reg_read(UC_X86_REG_DS)*16+uc.reg_read(UC_X86_REG_DX)
                output.append(bytes(uc.mem_read(address, 512)).split(b'$', 1)[0].decode('ascii'))
            else:
                assert ax >> 8 == 2
                output.append(chr(uc.reg_read(UC_X86_REG_DL)))

    def code(uc, address, size, _):
        nonlocal blocks, locked
        if address == 0x40000:
            assert not uc.reg_read(UC_X86_REG_EFLAGS) & 0x200
            fn = uc.reg_read(UC_X86_REG_AH)
            calls.append(fn)
            if fn == 9:
                kb = uc.reg_read(UC_X86_REG_DX)
                assert (not blocks and kb == 19) or (copy_only and len(blocks) == 1 and kb == 35)
                handle = len(blocks)+1
                blocks[handle] = bytearray(kb*1024)
                uc.reg_write(UC_X86_REG_DX, handle)
            elif fn in (0xc, 0xd):
                assert uc.reg_read(UC_X86_REG_DX) == 1
                assert (1 in locked) == (fn == 0xd)
                if fn == 0xc:
                    locked.add(1)
                else:
                    locked.remove(1)
                if fn == 0xc:
                    uc.reg_write(UC_X86_REG_DX, 0x20+len(sizes))
                    uc.reg_write(UC_X86_REG_BX, 0)
            elif fn == 0xf:
                assert not locked and uc.reg_read(UC_X86_REG_DX) == 1
                kb = uc.reg_read(UC_X86_REG_BX)
                sizes.append(kb)
                if reject_resize:
                    uc.reg_write(UC_X86_REG_AX, 0)
                    return
                assert kb*1024 > len(blocks[1])
                blocks[1].extend(bytes(kb*1024-len(blocks[1])))
            elif fn == 0xb:
                a = uc.reg_read(UC_X86_REG_DS)*16+uc.reg_read(UC_X86_REG_SI)
                count, sh, so, dh, do = struct.unpack('<IHIHI', bytes(uc.mem_read(a, 16)))
                assert count in (512, 19*1024)
                if sh == 0:
                    data = bytes(uc.mem_read((so >> 16)*16+(so & 65535), count))
                else:
                    assert sh in blocks and so+count <= len(blocks[sh])
                    data = bytes(blocks[sh][so:so+count])
                if dh == 0:
                    assert count == 512
                    if corrupt_copy:
                        data = bytes([data[0] ^ 1])+data[1:]
                    uc.mem_write((do >> 16)*16+(do & 65535), data)
                else:
                    assert dh in blocks and do+count <= len(blocks[dh])
                    blocks[dh][do:do+count] = data
            else:
                handle = uc.reg_read(UC_X86_REG_DX)
                assert fn == 0xa and handle not in locked and handle in blocks
                del blocks[handle]
            uc.reg_write(UC_X86_REG_AX, 1)
        elif bytes(uc.mem_read(address, 1)) == b'\xf4':
            parked.append(True)
            uc.emu_stop()

    u.hook_add(UC_HOOK_INTR, intr)
    u.hook_add(UC_HOOK_CODE, code)
    u.emu_start(0x20100, 0, count=200000)
    assert parked
    text = ''.join(output)
    if reject_resize or corrupt_copy:
        assert 'FAIL AX=' in text and 'PASS:' not in text
    else:
        assert 'PASS:' in text and 'FAIL' not in text and not blocks
        assert sizes == ([] if copy_only else [35, 51, 67, 83, 99, 115, 131])
    return dict(calls=calls, resize_kb=sizes, output=text)


if __name__ == '__main__':
    program = Path(sys.argv[1]).read_bytes()
    copy_only = '--copy' in sys.argv
    result = dict(passed=True, normal=run(program, copy_only=copy_only),
                  corrupted_copy=run(program, corrupt_copy=True, copy_only=copy_only))
    if not copy_only:
        result['rejected_resize'] = run(program, reject_resize=True)
    print(json.dumps(result, indent=2))
