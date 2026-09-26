#!/usr/bin/env python3
"""Exercise the actual COM program against independent DOS/XMS/RTC models.

This validates probe protocol, bounds, data checking, clock wrap and failure
handling. It is NOT a CPU/driver simulation or a hardware performance result.
No guest game code or disk image is used. Assemble xms_bench.asm separately.
"""
import json
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'build/verification-python'))
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_CODE
from unicorn.x86_const import *


def run(program, case='normal'):
    u = Uc(UC_ARCH_X86, UC_MODE_16)
    u.mem_map(0, 0x100000)
    u.mem_write(0x20100, program)
    u.mem_write(0x40000, b'\xcb')
    for reg, value in [(UC_X86_REG_CS, 0x2000), (UC_X86_REG_DS, 0x2000),
                       (UC_X86_REG_ES, 0x2000), (UC_X86_REG_SS, 0x2000),
                       (UC_X86_REG_SP, 0xfffe), (UC_X86_REG_EFLAGS, 0x202)]:
        u.reg_write(reg, value)
    state = dict(us=(86398 if case == 'midnight' else 43200)*1000000,
                 next_handle=1, rtc_reads=0, exited=None, created=False,
                 closed=False, saved=b'', copy_bytes=0, verify_bytes=0,
                 growth_verify_bytes=0, xms_calls=0, poisoned=False)
    blocks, output, allocs, resizes = {}, [], [], []

    def carry(value):
        flags = u.reg_read(UC_X86_REG_EFLAGS)
        u.reg_write(UC_X86_REG_EFLAGS, (flags | 1) if value else (flags & ~1))

    def far_address(segment_reg, offset_reg):
        return u.reg_read(segment_reg)*16+u.reg_read(offset_reg)

    def intr(uc, number, _):
        ax = uc.reg_read(UC_X86_REG_AX)
        if number == 0x2f:
            if ax == 0x4300:
                uc.reg_write(UC_X86_REG_AL, 0 if case == 'no_xms' else 0x80)
            else:
                assert ax == 0x4310
                uc.reg_write(UC_X86_REG_ES, 0x4000)
                uc.reg_write(UC_X86_REG_BX, 0)
            return
        if number == 0x1c:
            assert ax >> 8 == 0, 'RTC write/service other than read is forbidden'
            assert uc.reg_read(UC_X86_REG_EFLAGS) & 0x200
            state['rtc_reads'] += 1
            if case != 'clock_stopped':
                state['us'] += 2000
            seconds = (state['us']//1000000) % 86400
            def bcd(n):
                return (n//10)*16+n % 10
            calendar = bytes([0x26, 0x94, 0x25, bcd(seconds//3600),
                              bcd(seconds//60 % 60), bcd(seconds % 60)])
            if case == 'bad_bcd':
                calendar = calendar[:5]+b'\x6a'
            elif case == 'bad_hour':
                calendar = calendar[:3]+b'\x24'+calendar[4:]
            a = far_address(UC_X86_REG_ES, UC_X86_REG_BX)
            uc.mem_write(a, calendar)
            # The BIOS may clobber GPRs and segment registers. The caller must
            # restore its own state rather than relying on this model to do so.
            for reg in [UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX,
                        UC_X86_REG_EDX, UC_X86_REG_ESI, UC_X86_REG_EDI,
                        UC_X86_REG_EBP]:
                uc.reg_write(reg, 0xdeadbeef)
            uc.reg_write(UC_X86_REG_DS, 0x1000)
            uc.reg_write(UC_X86_REG_ES, 0x1000)
            return
        assert number == 0x21, hex(number)
        assert uc.reg_read(UC_X86_REG_EFLAGS) & 0x200, 'DOS called with IF clear'
        fn = ax >> 8
        if fn == 0x25:
            assert ax == 0x2524
        elif fn == 0x5b:
            a = far_address(UC_X86_REG_DS, UC_X86_REG_DX)
            assert bytes(uc.mem_read(a, 13)) == b'XMSBENCH.TXT\0'
            assert not state['created']
            carry(case == 'existing_file')
            uc.reg_write(UC_X86_REG_AX, 80 if case == 'existing_file' else 5)
            state['created'] = case != 'existing_file'
        elif fn == 2:
            output.append(chr(uc.reg_read(UC_X86_REG_DL)))
        elif fn == 0x40:
            assert state['created'] and not state['closed']
            assert uc.reg_read(UC_X86_REG_BX) == 5
            n = uc.reg_read(UC_X86_REG_CX)
            assert 0 < n <= 2048
            a = far_address(UC_X86_REG_DS, UC_X86_REG_DX)
            state['saved'] = bytes(uc.mem_read(a, n))
            carry(case == 'write_failure')
            uc.reg_write(UC_X86_REG_AX, 5 if case == 'write_failure' else n)
        elif fn == 0x3e:
            assert state['created'] and not state['closed']
            assert uc.reg_read(UC_X86_REG_BX) == 5
            state['closed'] = True
            carry(False)
        elif fn == 0x4c:
            state['exited'] = ax & 255
            uc.emu_stop()
        else:
            raise AssertionError('Unexpected DOS function %02x (no DOS clock allowed)' % fn)

    def xms(uc, address, size, _):
        assert address == 0x40000
        assert not uc.reg_read(UC_X86_REG_EFLAGS) & 0x200
        fn = uc.reg_read(UC_X86_REG_AH)
        state['xms_calls'] += 1
        if fn == 9:
            kb = uc.reg_read(UC_X86_REG_DX)
            allocs.append(kb)
            if case == 'allocation_failure':
                uc.reg_write(UC_X86_REG_AX, 0)
                uc.reg_write(UC_X86_REG_BL, 0xa0)
                return
            assert kb == [1043, 8192, 19, 1024, 1024][len(allocs)-1]
            handle = state['next_handle']
            state['next_handle'] += 1
            blocks[handle] = bytearray(kb*1024)
            uc.reg_write(UC_X86_REG_DX, handle)
            state['us'] += 250000
        elif fn == 0xf:
            handle, kb = uc.reg_read(UC_X86_REG_DX), uc.reg_read(UC_X86_REG_BX)
            assert handle == 3 and handle in blocks
            resizes.append(kb)
            assert kb == 19+16*len(resizes)
            assert len(resizes) <= 64
            if case == 'resize_failure' and len(resizes) == 7:
                uc.reg_write(UC_X86_REG_AX, 0)
                uc.reg_write(UC_X86_REG_BL, 0xa0)
                return
            blocks[handle].extend(bytes(kb*1024-len(blocks[handle])))
            if case == 'corrupt_growth' and len(resizes) == 64:
                blocks[handle][16383] ^= 1
            state['us'] += 3100000 if case == 'budget' else 100000
        elif fn == 0xb:
            a = far_address(UC_X86_REG_DS, UC_X86_REG_SI)
            n, sh, so, dh, do = struct.unpack('<IHIHI', bytes(uc.mem_read(a, 16)))
            assert n in (16384, 1048576)
            if sh:
                assert sh in blocks and so+n <= len(blocks[sh])
                data = bytes(blocks[sh][so:so+n])
            else:
                assert n == 16384
                data = bytes(uc.mem_read((so >> 16)*16+(so & 65535), n))
            if dh:
                assert dh in blocks and do+n <= len(blocks[dh])
                blocks[dh][do:do+n] = data
                if sh:
                    assert sh == 4 and dh == 5 and so == do == 0
                    assert n == 1048576
                    state['copy_bytes'] += n
                    if case == 'corrupt_copy':
                        # Last byte of the last chunk: sparse checks miss it.
                        blocks[dh][-1] ^= 1
                    state['us'] += 400000
            else:
                assert n == 16384
                uc.mem_write((do >> 16)*16+(do & 65535), data)
                if sh == 3:
                    state['growth_verify_bytes'] += n
                else:
                    assert sh == 5 and so == state['verify_bytes']
                    state['verify_bytes'] += n
            state['us'] += 1000
        else:
            assert fn == 0xa
            handle = uc.reg_read(UC_X86_REG_DX)
            assert handle in blocks
            del blocks[handle]
        uc.reg_write(UC_X86_REG_AX, 1)
        # A driver is allowed to return flags; the wrapper must restore IF.
        uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) | 0x200)

    u.hook_add(UC_HOOK_INTR, intr)
    u.hook_add(UC_HOOK_CODE, xms, begin=0x40000, end=0x40000)
    u.emu_start(0x20100, 0, count=30000000)
    assert state['exited'] is not None, (case, 'instruction budget exhausted')
    text = ''.join(output)
    expected = {
        'no_xms': 'FAIL: XMS driver absent',
        'bad_bcd': 'FAIL: invalid or non-advancing RTC',
        'bad_hour': 'FAIL: invalid or non-advancing RTC',
        'clock_stopped': 'FAIL: invalid or non-advancing RTC',
        'allocation_failure': 'FAIL: XMS function=9 AX=0 BL=160',
        'resize_failure': 'FAIL: XMS function=15 AX=0 BL=160',
        'corrupt_growth': 'FAIL: XMS data differs',
        'corrupt_copy': 'FAIL: XMS data differs',
        'budget': 'FAIL: phase exceeded 120 RTC seconds',
        'existing_file': 'ERROR: cannot create NEW',
        'write_failure': 'ERROR saving XMSBENCH.TXT',
    }
    if case in expected:
        assert expected[case] in text, (case, text)
        assert state['exited'] == (2 if case in ('existing_file', 'write_failure') else 1)
        if case != 'write_failure':
            assert 'PASS:' not in text
    else:
        assert state['exited'] == 0 and 'PASS:' in text and 'FAIL' not in text, text
        assert allocs == [1043, 8192, 19, 1024, 1024]
        assert resizes == list(range(35, 1044, 16))
        assert state['copy_bytes'] == 8*1048576
        assert state['verify_bytes'] == 1048576
        assert state['growth_verify_bytes'] == 16384
        seconds = list(map(int, re.findall(r'RTC_SECONDS=(\d+)', text)))
        assert len(seconds) == 4
        # Compare against the independently specified API costs and endpoint
        # quantization, not against values extracted from the implementation.
        for got, (lo, hi) in zip(seconds, [(0, 1), (0, 1), (6, 7), (3, 4)]):
            assert lo <= got <= hi, (case, seconds)
    assert not blocks, (case, 'allocated handles leaked')
    if state['created']:
        assert state['closed']
        assert state['saved'] == text.split('Saved new ')[0].split('ERROR saving ')[0].encode('ascii')
    else:
        assert state['xms_calls'] == 0 and state['saved'] == b''
    if case == 'budget':
        assert 1 < len(resizes) < 64
    return dict(case=case, exit=state['exited'], rtc_reads=state['rtc_reads'],
                requests=state['xms_calls'], resize_count=len(resizes),
                copy_bytes=state['copy_bytes'], verified_bytes=state['verify_bytes'],
                output=text)


if __name__ == '__main__':
    program = Path(sys.argv[1]).read_bytes()
    cases = ['normal', 'midnight', 'no_xms', 'bad_bcd', 'bad_hour', 'clock_stopped',
             'allocation_failure', 'resize_failure', 'corrupt_growth', 'corrupt_copy',
             'budget', 'existing_file', 'write_failure']
    print(json.dumps(dict(passed=True, cases=[run(program, case) for case in cases]), indent=2))
