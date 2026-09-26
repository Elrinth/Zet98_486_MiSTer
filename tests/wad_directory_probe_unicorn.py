"""Execute the self-authored DOS WAD probe against independent synthetic I/O."""
from pathlib import Path
import json
import struct
import sys
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'build/verification-python'))
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR
from unicorn.x86_const import *


def fixture(count=2045):
    directory = bytearray()
    special = {3: b'DEMO1', 5: b'DEMO3', 466: b'TITLEPIC',
               502: b'E1M1', 512: b'E1M2', 2000: b'DEMO1'}
    for i in range(count):
        name = special.get(i, ('L%07d' % i).encode()).ljust(8, b'\0')
        directory += struct.pack('<II8s', 12 + i, i % 19, name)
    data = bytearray(0x20013) + directory
    data[:12] = struct.pack('<4sII', b'IWAD', count, 0x20013)
    return data, bytes(directory)


def run(binary, case):
    data, directory = fixture(2048 if case == 'max_count' else 2045)
    if case == 'signature': data[:4] = b'XXXX'
    if case == 'zero_count': struct.pack_into('<I', data, 4, 0)
    if case == 'large_count': struct.pack_into('<I', data, 4, 2049)
    if case == 'directory_overflow': struct.pack_into('<I', data, 8, 0xfffffff0)
    if case == 'directory_bounds': struct.pack_into('<I', data, 8, len(data))
    if case == 'entry_bounds': struct.pack_into('<I', data, 0x20013, len(data) + 1)
    if case == 'entry_overflow': struct.pack_into('<II', data, 0x20013, 0xfffffff0, 32)
    u = Uc(UC_ARCH_X86, UC_MODE_16)
    u.mem_map(0, 0x200000)
    u.mem_write(0x10100, binary)
    u.mem_write(0x10002, b'\0\x90')
    for reg in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
        u.reg_write(reg, 0x1000)
    u.reg_write(UC_X86_REG_SP, 0xfffe)
    u.reg_write(UC_X86_REG_EFLAGS, 0x602 if case == 'df_set' else 0x202)
    state = dict(position=0, reads=0, written=b'', created=False, exit=None)

    def intr(uc, number, _):
        assert number == 0x21
        ax = uc.reg_read(UC_X86_REG_AX)
        ah = ax >> 8
        dx = uc.reg_read(UC_X86_REG_DX)
        cx = uc.reg_read(UC_X86_REG_CX)
        ptr = uc.reg_read(UC_X86_REG_DS) * 16 + dx
        uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) & ~1)
        if ah == 9: return
        if ah == 0x3d:
            assert bytes(uc.mem_read(ptr, 32)).split(b'\0')[0] == b'A:\\DOOM1\\DOOM.WAD'
            assert ax & 0xff == 0
            uc.reg_write(UC_X86_REG_AX, 7)
        elif ah == 0x42:
            assert uc.reg_read(UC_X86_REG_BX) == 7
            if case == 'seek_error':
                uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) | 1)
                return
            state['position'] = len(data) if ax & 0xff == 2 else (cx << 16) | dx
            uc.reg_write(UC_X86_REG_AX, state['position'] & 0xffff)
            uc.reg_write(UC_X86_REG_DX, state['position'] >> 16)
        elif ah == 0x3f:
            assert uc.reg_read(UC_X86_REG_BX) == 7
            assert cx <= 1024 and dx + cx <= 65536
            amount = cx - 1 if case == 'short_read' and state['reads'] == 2 else cx
            chunk = bytes(data[state['position']:state['position'] + amount])
            uc.mem_write(ptr, chunk)
            state['position'] += len(chunk)
            state['reads'] += 1
            uc.reg_write(UC_X86_REG_AX, len(chunk))
        elif ah == 0x5b:
            assert bytes(uc.mem_read(ptr, 32)).split(b'\0')[0] == b'A:\\WADDIR.BIN'
            if case == 'existing_result':
                uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) | 1)
            else:
                state['created'] = True
                uc.reg_write(UC_X86_REG_AX, 8)
        elif ah == 0x40:
            assert state['created'] and uc.reg_read(UC_X86_REG_BX) == 8
            amount = cx - 1 if case == 'short_write' else cx
            state['written'] += bytes(uc.mem_read(ptr, amount))
            uc.reg_write(UC_X86_REG_AX, amount)
        elif ah in (0x3e, 0x0d): pass
        elif ah == 0x4c:
            state['exit'] = ax & 255
            uc.emu_stop()
        else: raise AssertionError(hex(ax))

    u.hook_add(UC_HOOK_INTR, intr)
    u.emu_start(0x10100, 0, count=5000000)
    good = case in ('normal', 'max_count', 'df_set')
    assert state['exit'] == (0 if good else 1), (case, state['exit'])
    if good:
        r = state['written']
        count = len(directory) // 16
        assert r[:8] == b'Z98WAD1\0' and len(r) == 64 + len(directory)
        assert struct.unpack_from('<I', r, 8)[0] == len(data)
        assert r[12:24] == data[:12] and r[64:] == directory
        assert struct.unpack_from('<II', r, 24) == (zlib.crc32(directory), count)
        assert struct.unpack_from('<5I', r, 32) == (2000, 5, 466, 502, 512)
        assert r[52:64] == bytes(12)
    return dict(case=case, passed=True, exit=state['exit'], reads=state['reads'])


if __name__ == '__main__':
    binary = Path(sys.argv[1]).read_bytes()
    cases = ['normal', 'max_count', 'df_set', 'signature', 'zero_count',
             'large_count', 'directory_overflow', 'directory_bounds',
             'entry_bounds', 'entry_overflow', 'short_read', 'seek_error',
             'existing_result', 'short_write']
    print(json.dumps(dict(passed=True, cases=[run(binary, c) for c in cases]), indent=2))
