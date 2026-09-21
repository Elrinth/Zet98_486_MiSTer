#!/usr/bin/env python3
"""Check the silent polled-ACK diagnostic against edge/level pending-IRQ models; requires unicorn==2.1.4.

This models DOS calls and an independent minimal MPU/PIC. RTL and physical
serial behavior are tested separately. No owner ROM/DOS/game files are used.
"""
import struct
import sys
from pathlib import Path
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_CODE, UC_HOOK_INTR, UC_HOOK_INSN
from unicorn.x86_const import *


def run(binary, pending_model, fault=None):
    u = Uc(UC_ARCH_X86, UC_MODE_16)
    u.mem_map(0, 0x200000)
    u.mem_write(0x10100, binary)
    original_vector = struct.pack('<HH', 0x5678, 0x1234)
    u.mem_write(0x0e*4, original_vector)
    u.reg_write(UC_X86_REG_CS, 0x1000)
    state = dict(mask=0xff, ack=False, pending=False, mode=False, irqs=0, irr_read=False, printed=bytearray(),
                 eois=0, ticks=0, halted=False, log=bytearray())

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
        elif ah == 9:
            addr=ds*16+dx
            while uc.mem_read(addr,1)!=b'$':
                state['printed'].extend(uc.mem_read(addr,1));addr+=1
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
        if port == 0:
            assert state['irr_read']
            return 0x40 if state['pending'] else 0
        if port == 2:
            return state['mask']
        if port == 0xe0d2:
            busy = fault == 'busy'
            return (0 if state['ack'] else 0x80) | (0x40 if busy else 0)
        assert port == 0xe0d0
        assert state['ack']
        state['ack'] = False
        if pending_model == 'level':
            state['pending'] = False
        return 0x42 if fault == 'bad_ack' else 0xfe

    def outp(uc, port, size, value, _):
        assert size == 1
        if port == 2:
            state['mask'] = value
        elif port == 0:
            assert value in (0x20,0x0a)
            if value==0x0a:state['irr_read']=True
            else:state['eois'] += 1
        elif port == 0xe0d2:
            assert value == 0x3f and not state['mode']
            state['mode'] = True
            state['ack'] = fault != 'missing_ack'
            state['pending'] = state['ack']
        else:
            raise AssertionError('Unexpected output: probe must not transmit MIDI data')

    def instruction(uc, address, size, _):
        flags = uc.reg_read(UC_X86_REG_EFLAGS)
        if state['pending'] and not state['mask'] & 0x40 and flags & 0x200:
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
            state['halted'] = True
            uc.emu_stop()

    u.hook_add(UC_HOOK_INTR, dos)
    u.hook_add(UC_HOOK_CODE, instruction)
    u.hook_add(UC_HOOK_INSN, inp, None, 1, 0, UC_X86_INS_IN)
    u.hook_add(UC_HOOK_INSN, outp, None, 1, 0, UC_X86_INS_OUT)
    u.emu_start(0x10100, 0x200000, count=1000000)
    assert u.mem_read(0x0e*4, 4) == original_vector, 'IRQ vector not restored'
    assert state['mask'] == 0xff, 'PIC mask not restored'
    assert state['halted'], 'Diagnostic exceeded instruction budget'
    retained = pending_model == 'edge' and fault not in ('busy', 'missing_ack')
    expected_ack = '00' if fault in ('busy', 'missing_ack') else '42' if fault=='bad_ack' else 'FE'
    expected = ('MPU polled UART ACK=' + expected_ack +
                (' IRR=40 IRQ=01 EMPTY=01' if retained else ' IRR=00 IRQ=00 EMPTY=00')).encode()
    assert expected in state['log'], state['log']
    assert state['printed'] == state['log']
    assert state['irqs'] == int(retained)
    print('PASS polled-ACK diagnostic:', pending_model, fault, state['log'].decode().splitlines()[0])



if __name__ == '__main__':
    binary = Path(sys.argv[1]).read_bytes()
    for pending_model in ('edge', 'level'):
        for fault in (None, 'busy', 'missing_ack', 'bad_ack'):
            run(binary, pending_model, fault)
