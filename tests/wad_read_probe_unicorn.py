"""Self-authored DOS probe protocol test: independent bytes, zlib CRC and RTC."""
from pathlib import Path
import json
import struct
import sys
import zlib
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'build/verification-python'))
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR
from unicorn.x86_const import *


def run(binary, case):
    size = 1048593 if case == 'megabyte' else 98323
    data = bytes((i * 37 + (i >> 8) + (i >> 16)) & 255 for i in range(size))
    if case == 'minimum': data = data[:12]
    if case == 'exact_chunk': data = data[:32768]
    if case == 'chunk_plus_one': data = data[:32769]
    if case == 'tiny': data = data[:11]
    u = Uc(UC_ARCH_X86, UC_MODE_16)
    u.mem_map(0, 0x200000)
    u.mem_write(0x10100, binary)
    u.mem_write(0x10002, b'\0\x90')
    for reg in (UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_ES, UC_X86_REG_SS):
        u.reg_write(reg, 0x1000)
    u.reg_write(UC_X86_REG_SP, 0xfffe)
    u.reg_write(UC_X86_REG_EFLAGS, 0x602 if case == 'df_set' else 0x202)
    s = dict(position=0, reads=0, passnum=0, rtc=0, written=b'', created=False, exit=None)
    def intr(uc, number, _):
        ax, bx, cx, dx = [uc.reg_read(r) for r in
                         (UC_X86_REG_AX, UC_X86_REG_BX, UC_X86_REG_CX, UC_X86_REG_DX)]
        ptr = uc.reg_read(UC_X86_REG_DS) * 16 + dx
        def error(): uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) | 1)
        uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) & ~1)
        if number == 0x1c:
            assert ax >> 8 == 0
            s['rtc'] += 1
            seconds = (s['rtc'] if case != 'frozen_clock' else 1)
            if case == 'timeout' and s['reads']: seconds += 120
            if case == 'midnight': seconds += 86396
            seconds %= 86400
            hour, minute, second = seconds // 3600, seconds // 60 % 60, seconds % 60
            def bcd(x): return (x // 10) * 16 + x % 10
            clock = bytes([0, 0, 0, bcd(hour), bcd(minute), bcd(second)])
            if case == 'bad_bcd': clock = clock[:5] + b'\x1a'
            if case == 'bad_hour': clock = clock[:3] + b'\x24' + clock[4:]
            uc.mem_write(uc.reg_read(UC_X86_REG_ES) * 16 + bx, clock)
            return
        assert number == 0x21
        ah = ax >> 8
        if ah in (9, 0x25, 0x0d): return
        if ah == 0x5b:
            assert bytes(uc.mem_read(ptr, 32)).split(b'\0')[0] == b'A:\\WADREAD.BIN'
            if case == 'existing': error()
            else: s['created'] = True; uc.reg_write(UC_X86_REG_AX, 8)
        elif ah == 0x3d:
            assert bytes(uc.mem_read(ptr, 32)).split(b'\0')[0] == b'A:\\DOOM1\\DOOM.WAD'
            assert ax & 255 == 0
            if case == 'open_error': error()
            else: uc.reg_write(UC_X86_REG_AX, 7)
        elif ah == 0x42:
            assert bx == 7 and cx == dx == 0
            if case == 'seek_error': error(); return
            s['position'] = (0x2000001 if case == 'too_large' else len(data)) if ax & 255 == 2 else 0
            if ax & 255 == 0: s['passnum'] += 1
            uc.reg_write(UC_X86_REG_AX, s['position'] & 65535)
            uc.reg_write(UC_X86_REG_DX, s['position'] >> 16)
        elif ah == 0x3f:
            assert bx == 7 and 0 < cx <= 32768 and dx + cx <= 65536
            s['reads'] += 1
            if case == 'read_error': error(); return
            chunk = data[s['position']:s['position']+cx]
            if case == 'short_read' and s['reads'] == 2: chunk = chunk[:-1]
            if case == 'growth' and s['position'] == len(data): chunk = b'!'
            if case == 'corrupt' and s['passnum'] == 2 and s['position'] == 32768:
                chunk = bytes([chunk[0] ^ 1]) + chunk[1:]
            if chunk: uc.mem_write(ptr, chunk)
            s['position'] += len(chunk)
            uc.reg_write(UC_X86_REG_AX, len(chunk))
        elif ah == 0x40:
            assert bx == 8 and s['created']
            amount = cx-1 if case == 'short_write' else cx
            s['written'] += bytes(uc.mem_read(ptr, amount))
            uc.reg_write(UC_X86_REG_AX, amount)
        elif ah == 0x3e: pass
        elif ah == 0x4c: s['exit'] = ax & 255; uc.emu_stop()
        else: raise AssertionError(hex(ax))
    u.hook_add(UC_HOOK_INTR, intr)
    u.emu_start(0x10100, 0, count=30000000)
    good = case in ('normal', 'megabyte', 'minimum', 'exact_chunk', 'chunk_plus_one', 'df_set', 'midnight', 'corrupt')
    assert s['exit'] == (0 if good else 1), (case, s['exit'])
    if good:
        r = s['written']; n = (len(data)+32767)//32768
        assert r[:8] == b'Z98READ1' and len(r) == 64+4*n
        length, raw_secs, crc_secs, crc, chunks, chunk_size = struct.unpack_from('<6I', r, 8)
        assert (length, chunks, chunk_size) == (len(data), n, 32768)
        assert raw_secs == crc_secs == n+1 and r[32:64] == bytes(32)
        expected = [zlib.crc32(data[:min((i+1)*32768, len(data))]) for i in range(n)]
        actual = list(struct.unpack_from('<%dI' % n, r, 64))
        if case == 'corrupt':
            assert actual[0] == expected[0] and actual[1:] != expected[1:] and crc != zlib.crc32(data)
        else: assert actual == expected and crc == zlib.crc32(data)
    return dict(case=case, passed=True, exit=s['exit'], reads=s['reads'])


if __name__ == '__main__':
    cases = ['normal','megabyte','minimum','exact_chunk','chunk_plus_one','df_set','midnight','corrupt','tiny','too_large',
             'existing','open_error','seek_error','read_error','short_read','growth',
             'short_write','bad_bcd','bad_hour','frozen_clock','timeout']
    print(json.dumps(dict(passed=True, cases=[run(Path(sys.argv[1]).read_bytes(), c) for c in cases]), indent=2))
