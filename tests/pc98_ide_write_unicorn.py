#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Execute the actual 386 BIOS with an independent mutable PIO disk model."""
import struct
import sys
from pathlib import Path
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_INSN
from unicorn.x86_const import *


class Machine:
    def __init__(self, binary):
        assert binary[:4] == b'Z98W'
        self.u = Uc(UC_ARCH_X86, UC_MODE_16)
        self.u.mem_map(0, 0x200000)
        self.u.mem_write(0x1000, binary)
        self.u.mem_write(0x1b * 4, struct.pack('<HH', struct.unpack_from('<H', binary, 4)[0], 0))
        self.ports = {}
        self.disk = {}
        self.commands = []
        self.status = 0x50
        self.delay = 0
        self.fault = None
        self.u.hook_add(UC_HOOK_INTR, self.interrupt)
        self.u.hook_add(UC_HOOK_INSN, self.input, None, 1, 0, UC_X86_INS_IN)
        self.u.hook_add(UC_HOOK_INSN, self.output, None, 1, 0, UC_X86_INS_OUT)

    def sector(self, lba):
        return self.disk.get(lba, b''.join(struct.pack('<H', (0xa55a ^ lba ^ n) & 65535) for n in range(256)))

    def output(self, u, port, size, value, data):
        self.ports[port] = value
        if port == 0x64e:
            assert size == 1 and value in (0x20, 0x30)
            assert self.ports[0x644] == 1 and self.ports[0x74c] == 2
            self.lba = (self.ports[0x646] | self.ports[0x648] << 8 |
                        self.ports[0x64a] << 16 | (self.ports[0x64c] & 15) << 24)
            self.command = value
            if value == 0x30:
                assert 17 <= self.lba <= 100000, 'write escaped the explicit window'
            self.commands.append((value, self.lba))
            self.word = 0
            self.buffer = bytearray(self.sector(self.lba))
            self.delay = 3
            self.next_status = 0x51 if self.fault == 'command' else 0x58
            self.status = 0x80
        elif port == 0x640:
            assert size == 2 and self.command == 0x30 and self.status == 0x58
            struct.pack_into('<H', self.buffer, self.word * 2, value)
            self.word += 1
            if self.word == 256:
                self.disk[self.lba] = bytes(self.buffer)
                self.status, self.delay = 0x80, 4
                self.next_status = {'completion': 0x51, 'device_fault': 0x70,
                                    'stuck_drq': 0x58, 'lost_device': 0}.get(self.fault, 0x50)

    def input(self, u, port, size, data):
        if port in (0x74c, 0x64e):
            assert size == 1
            if self.fault == 'busy':
                return 0x80
            if self.fault == 'absent':
                return 0
            if self.delay:
                self.delay -= 1
                if not self.delay:
                    self.status = self.next_status
            return self.status
        if port == 0x640:
            assert size == 2 and self.command == 0x20 and self.status == 0x58
            value = struct.unpack_from('<H', self.buffer, self.word * 2)[0]
            self.word += 1
            if self.word == 256:
                self.status = 0x50
            return value
        return self.ports.get(port, (1 << (size * 8)) - 1)

    @staticmethod
    def interrupt(u, vector, data):
        flags = u.reg_read(UC_X86_REG_EFLAGS)
        sp, ss = u.reg_read(UC_X86_REG_SP), u.reg_read(UC_X86_REG_SS)
        for value in (flags, u.reg_read(UC_X86_REG_CS), u.reg_read(UC_X86_REG_IP)):
            sp = (sp - 2) & 65535
            u.mem_write(ss * 16 + sp, struct.pack('<H', value & 65535))
        u.reg_write(UC_X86_REG_SP, sp)
        u.reg_write(UC_X86_REG_EFLAGS, flags & ~0x300)
        ip, cs = struct.unpack('<HH', u.mem_read(vector * 4, 4))
        u.reg_write(UC_X86_REG_CS, cs)
        u.reg_write(UC_X86_REG_IP, ip)

    def call(self, lba, payload, *, chs=False, offset=0xfff0, command=5,
             error=0, byte_count=None, es=0x2000, device=None):
        u = self.u
        size = len(payload) if byte_count is None else byte_count
        address = es * 16 + offset
        if payload:
            u.mem_write(address, payload)
        guard = bytes(u.mem_read(address, max(len(payload), 1) + 2))
        if chs:
            cylinder, rem = divmod(lba, 8 * 17)
            head, sector = divmod(rem, 17)
            cx, dx = cylinder, head * 256 + sector
        else:
            cx, dx = lba & 65535, lba >> 16
        regs = {UC_X86_REG_EAX: 0x12340000 | command << 8 | (device if device is not None else 0x80 if chs else 0),
                UC_X86_REG_EBX: 0x56780000 | (size & 65535), UC_X86_REG_ECX: 0x9abc0000 | cx,
                UC_X86_REG_EDX: 0xdef00000 | dx, UC_X86_REG_EBP: 0x24680000 | offset,
                UC_X86_REG_ESI: 0x13572468, UC_X86_REG_EDI: 0x89abcdef,
                UC_X86_REG_DS: 0x1234, UC_X86_REG_ES: es,
                UC_X86_REG_SS: 0x1000, UC_X86_REG_ESP: 0x9000,
                UC_X86_REG_CS: 0, UC_X86_REG_IP: 0x1008, UC_X86_REG_EFLAGS: 0x647}
        for reg, value in regs.items():
            u.reg_write(reg, value)
        u.emu_start(0x1008, 0x100b, count=3000000)
        assert u.reg_read(UC_X86_REG_IP) == 0x100b, 'BIOS failed to return'
        assert u.reg_read(UC_X86_REG_AH) == error, (hex(u.reg_read(UC_X86_REG_AX)), error)
        for reg in (UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDX, UC_X86_REG_EBP,
                    UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_DS, UC_X86_REG_ES,
                    UC_X86_REG_SS, UC_X86_REG_ESP):
            assert u.reg_read(reg) == regs[reg], ('register changed', reg)
        assert u.reg_read(UC_X86_REG_EAX) & 0xffff00ff == regs[UC_X86_REG_EAX] & 0xffff00ff
        flags = u.reg_read(UC_X86_REG_EFLAGS)
        assert flags & 0xfffe == regs[UC_X86_REG_EFLAGS] & 0xfffe, 'caller flags changed'
        assert bool(flags & 1) == bool(error >= 0x20)
        if command == 5:
            assert bytes(u.mem_read(address, max(len(payload), 1) + 2)) == guard, 'write modified caller buffer'


binary = Path(sys.argv[1]).read_bytes()
m = Machine(binary)
cases = 0
for lba, size, chs in [(17, 512, False), (543, 1536, True), (0x10123, 513, False),
                       (100, 65536, False), (99999, 1024, False), (999, 1, True),
                       (1001, 511, False), (1003, 1023, False)]:
    count = (size + 511) // 512
    before = b''.join(m.sector(lba + n) for n in range(count))
    payload = bytes((i * 31 + lba) & 255 for i in range(size))
    commands = len(m.commands)
    m.call(lba, payload, chs=chs)
    after = b''.join(m.sector(lba + n) for n in range(count))
    assert after == payload + before[size:], (lba, size, 'disk data/tail mismatch')
    assert m.commands[commands:] == ([(0x30, lba + n) for n in range(size // 512)] +
           ([(0x20, lba + count - 1), (0x30, lba + count - 1)] if size % 512 else []))
    assert m.ports[0x74c] == 0 and m.status == 0x50, 'write returned before completion'
    m.call(lba, bytes([0xcc]) * size, chs=chs, command=6)
    assert bytes(m.u.mem_read(0x2fff0, size)) == payload, 'BIOS readback mismatch'
    cases += 1
for lba, size, error, extra in [(16, 512, 0x70, {}), (100000, 513, 0x70, {}),
                              (8162 * 8 * 17, 512, 0xd0, {}),
                              (17, 512, 0xd0, {'es': 0xffff, 'offset': 0}),
                              (17, 0, 0xd0, {'es': 0xffff, 'offset': 0})]:
    count, disk = len(m.commands), dict(m.disk)
    m.call(lba, b'', byte_count=size, error=error, **extra)
    assert len(m.commands) == count and m.disk == disk, 'rejected request touched disk'
    cases += 1
count = len(m.commands)
m.call(17, b'unchanged', device=0x81, error=0xaa)
assert len(m.commands) == count, 'other drive was not chained'
cases += 1
for fault in ('absent', 'busy', 'command', 'completion', 'device_fault', 'stuck_drq', 'lost_device'):
    m = Machine(binary)
    m.fault = fault
    m.call(17, bytes(range(256)) * 2, error=0x60)
    assert m.ports.get(0x74c) == 0, 'error left polled IRQ suppression enabled'
    if fault in ('absent', 'busy', 'command'):
        assert not m.disk
    cases += 1
print('PASS: {} BIOS write cases; CHS/LBA, 64K, segment crossing, partial tails, bounds, ABI and ATA failures'.format(cases))
