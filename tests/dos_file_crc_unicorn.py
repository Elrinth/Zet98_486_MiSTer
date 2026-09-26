#!/usr/bin/env python3
"""Execute the file probe with synthetic DOS files, including 64 KiB crossing."""
import json
import struct
import sys
import zlib
from pathlib import Path
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR
from unicorn.x86_const import *

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_dos_file_crc_probe import verify

files = [(b'EMPTY.BZH', b''), (b'ONE.GZH', b'\x81'),
         (b'ODD.GZH', bytes((i*37+9) & 255 for i in range(1025))),
         (b'C_\xc5\xb6\xc9.BZH', bytes((i*73+(i >> 8)) & 255 for i in range(70001)))]
u = Uc(UC_ARCH_X86, UC_MODE_16)
u.mem_map(0, 0x200000)
u.mem_write(0x10100, Path(sys.argv[1]).read_bytes())
u.mem_write(0x10002, b'\0\x90')
for r in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
    u.reg_write(r, 0x1000)
state = dict(index=0, position=0, done=False)
capture = bytearray()


def interrupt(uc, number, _):
    assert number == 0x21
    ax = uc.reg_read(UC_X86_REG_AX)
    ah = ax >> 8
    address = uc.reg_read(UC_X86_REG_DS)*16 + uc.reg_read(UC_X86_REG_DX)
    carry = False
    if ah == 0x0e:
        assert uc.reg_read(UC_X86_REG_DX) & 255 == 1
    elif ah == 0x1a:
        state['dta'] = address
    elif ah in (0x4e, 0x4f):
        if ah == 0x4f:
            state['index'] += 1
        if state['index'] == len(files):
            uc.reg_write(UC_X86_REG_AX, 18)
            carry = True
        else:
            name, data = files[state['index']]
            dta = bytearray(43)
            struct.pack_into('<I', dta, 26, len(data))
            dta[30:30+len(name)] = name
            uc.mem_write(state['dta'], bytes(dta))
    elif ah == 0x3d:
        assert bytes(uc.mem_read(address, 13)).split(b'\0')[0] == files[state['index']][0]
        state['position'] = 0
        uc.reg_write(UC_X86_REG_AX, 5)
    elif ah == 0x3f:
        data = files[state['index']][1]
        chunk = data[state['position']:state['position']+uc.reg_read(UC_X86_REG_CX)]
        if chunk:
            uc.mem_write(address, chunk)
        state['position'] += len(chunk)
        uc.reg_write(UC_X86_REG_AX, len(chunk))
    elif ah == 0x5b:
        uc.reg_write(UC_X86_REG_AX, 6)
    elif ah == 0x40:
        length = uc.reg_read(UC_X86_REG_CX)
        capture.extend(uc.mem_read(address, length))
        uc.reg_write(UC_X86_REG_AX, length)
    elif ah == 9:
        message = bytes(uc.mem_read(address, 80)).split(b'$')[0]
        if b'CRC32 saved' in message:
            state['done'] = True
            uc.emu_stop()
        else:
            assert message in (b'File CRC probe started\r\n',
                               b'Reading graphics from B:\r\n', b'.'), message
    else:
        assert ah in (0x25, 0x3e, 0x0d)
    flags = uc.reg_read(UC_X86_REG_EFLAGS) & ~1
    uc.reg_write(UC_X86_REG_EFLAGS, flags | int(carry))


u.hook_add(UC_HOOK_INTR, interrupt)
u.emu_start(0x10100, 0, count=10000000)
assert state['done']
expected = [dict(name_hex=name.hex(), size=len(data), crc32=zlib.crc32(data))
            for name, data in files]
result = verify(capture, expected)
assert result['passed'], result
capture[36] ^= 1
assert not verify(capture, expected)['passed']
print(json.dumps(dict(reference=result, negative_control='PASS'), indent=2))
