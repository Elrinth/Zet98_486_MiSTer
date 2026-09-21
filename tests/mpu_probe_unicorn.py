#!/usr/bin/env python3
"""Check the DOS MPU diagnostic itself; requires unicorn==2.1.4.

This models DOS calls and an independent minimal MPU/PIC. RTL and physical
serial behavior are tested separately. No owner ROM/DOS/game files are used.
"""
import struct
import sys
from pathlib import Path
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_CODE, UC_HOOK_INTR, UC_HOOK_INSN
from unicorn.x86_const import *


def run(binary, fault):
    u = Uc(UC_ARCH_X86, UC_MODE_16)
    u.mem_map(0, 0x200000)
    u.mem_write(0x10100, binary)
    original_vector = struct.pack('<HH', 0x5678, 0x1234)
    u.mem_write(0x0e*4, original_vector)
    u.reg_write(UC_X86_REG_CS, 0x1000)
    state = dict(mask=0xff, ack=False, pending=False, mode=False, irqs=0,
                 eois=0, ticks=0, busy=0, stream=bytearray(), log=bytearray())

    def dos(uc, vector, _):
        assert vector == 0x21, hex(vector)
        ax = uc.reg_read(UC_X86_REG_AX)
        dx = uc.reg_read(UC_X86_REG_DX)
        ds = uc.reg_read(UC_X86_REG_DS)
        ah, al = ax >> 8, ax & 255
        uc.reg_write(UC_X86_REG_EFLAGS, uc.reg_read(UC_X86_REG_EFLAGS) & ~1)
        if ah == 0x25:
            uc.mem_write(al*4, struct.pack('<HH', dx, ds))
        elif ah == 0x35:
            ip, cs = struct.unpack('<HH', uc.mem_read(al*4, 4))
            uc.reg_write(UC_X86_REG_BX, ip)
            uc.reg_write(UC_X86_REG_ES, cs)
        elif ah == 0x2c:
            state['ticks'] += 1
            uc.reg_write(UC_X86_REG_DX, ((state['ticks']//16) % 60) << 8)
        elif ah == 0x3c:
            uc.reg_write(UC_X86_REG_AX, 5)
        elif ah == 0x40:
            n = uc.reg_read(UC_X86_REG_CX)
            state['log'].extend(uc.mem_read(ds*16+dx, n))
            uc.reg_write(UC_X86_REG_AX, n)
        else:
            assert ah in (2, 0x3e, 0x0d), hex(ax)

    def inp(uc, port, size, _):
        assert size == 1
        if port == 2:
            return state['mask']
        if port == 0xe0d2:
            busy = state['busy'] > 0 or (fault == 'busy' and state['irqs'] == 200)
            state['busy'] = max(0, state['busy']-1)
            return (0 if state['ack'] else 0x80) | (0x40 if busy else 0)
        assert port == 0xe0d0
        assert state['ack']
        state['ack'] = False
        return 0x42 if fault == 'bad_ack' else 0xfe

    def outp(uc, port, size, value, _):
        assert size == 1
        if port == 2:
            state['mask'] = value
        elif port == 0:
            assert value == 0x20
            state['eois'] += 1
        elif port == 0xe0d2:
            assert value == 0xff or (value == 0x3f and not state['mode'])
            acknowledge = not (value == 0xff and state['mode']) or fault == 'uart_reset_ack'
            state['mode'] = value == 0x3f
            state['ack'] = acknowledge
            state['pending'] = acknowledge
        else:
            assert port == 0xe0d0 and state['mode'] and not state['busy']
            state['stream'].append(value)
            state['busy'] = 3

    def instruction(uc, address, size, _):
        flags = uc.reg_read(UC_X86_REG_EFLAGS)
        if state['pending'] and not state['mask'] & 0x40 and flags & 0x200 and fault != 'no_irq':
            state['pending'] = False
            state['irqs'] += 1
            sp = uc.reg_read(UC_X86_REG_SP)
            ss = uc.reg_read(UC_X86_REG_SS)
            for word in (flags, uc.reg_read(UC_X86_REG_CS), uc.reg_read(UC_X86_REG_IP)):
                sp = (sp-2) & 65535
                uc.mem_write(ss*16+sp, struct.pack('<H', word & 65535))
            uc.reg_write(UC_X86_REG_SP, sp)
            uc.reg_write(UC_X86_REG_EFLAGS, flags & ~0x300)
            ip, cs = struct.unpack('<HH', uc.mem_read(0x0e*4, 4))
            uc.reg_write(UC_X86_REG_CS, cs)
            uc.reg_write(UC_X86_REG_IP, ip)
        elif uc.mem_read(address, 1) == b'\xf4':
            uc.emu_stop()

    u.hook_add(UC_HOOK_INTR, dos)
    u.hook_add(UC_HOOK_CODE, instruction)
    u.hook_add(UC_HOOK_INSN, inp, None, 1, 0, UC_X86_INS_IN)
    u.hook_add(UC_HOOK_INSN, outp, None, 1, 0, UC_X86_INS_OUT)
    u.emu_start(0x10100, 0x200000, count=1000000)
    assert u.mem_read(0x0e*4, 4) == original_vector, 'IRQ vector not restored'
    assert state['mask'] == 0xff, 'PIC mask not restored'
    if fault is None:
        assert b'PASS: 200 MPU' in state['log'], state['log']
        assert state['irqs'] == 200 and state['eois'] == 201, state
        assert state['stream'] == b'\xf0\x7dZ98' + bytes(range(128)) + b'\xf7'
    else:
        assert b'FAIL:' in state['log'] and b'PASS:' not in state['log'], state['log']
    print('PASS DOS MPU diagnostic:', fault or '200 IRQs, cleanup, exact 134-byte serial payload')


if __name__ == '__main__':
    binary = Path(sys.argv[1]).read_bytes()
    for fault in (None, 'no_irq', 'bad_ack', 'busy', 'uart_reset_ack'):
        run(binary, fault)
