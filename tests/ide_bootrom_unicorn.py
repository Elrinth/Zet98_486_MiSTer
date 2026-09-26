#!/usr/bin/env python3
"""Execute the real option-ROM entry table, geometry scan, IPL and disk service."""
import argparse
import struct
from pathlib import Path
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INSN, UC_HOOK_INTR, UC_HOOK_CODE, UC_HOOK_MEM_WRITE
from unicorn.x86_const import *


def synthetic(heads=8, sectors=17, cylinders=1024):
    capacity = heads*sectors*cylinders
    ipl = bytearray(1024)
    ipl[:4] = b'\xeb\x02\x90\x90'
    ipl[510:512] = b'\x55\xaa'
    ipl[512:514] = b'\xa1\xa1'
    struct.pack_into('<H', ipl, 518, 1)
    struct.pack_into('<H', ipl, 522, 1)
    bpb = bytearray(512)
    bpb[:3] = b'\xeb\x3c\x90'
    struct.pack_into('<HBHBHHBHHHI', bpb, 11, 512, 8, 1, 2, 512, 0,
                     0xf8, 10, sectors, heads, heads*sectors)
    struct.pack_into('<I', bpb, 32, capacity-heads*sectors)
    return capacity, {0:bytes(ipl[:512]), 1:bytes(ipl[512:]), heads*sectors:bytes(bpb)}


class Machine:
    def __init__(self, rom, heads=8, sectors=17, image=None, absent=False, bad_bpb=False, readonly=False):
        self.u = Uc(UC_ARCH_X86, UC_MODE_16)
        # 64 MB flat map: the ROM's Z98MEM probe checks every megabyte.
        self.u.mem_map(0, 0x4000000)
        self.u.mem_write(0xd0000, rom)
        # The legacy BIOS sets the V30 flag (bit 6) and bit 5 unconditionally.
        self.u.mem_write(0x501, bytes([0x63]))
        # PRXDUPD as NP2kai's BIOS initializes it without an EGC (0x18).
        self.u.mem_write(0x54d, bytes([0x18]))
        self.original_vector = struct.pack('<HH', 0x1a82, 0xfd80)
        self.u.mem_write(0x6c, self.original_vector)
        self.capacity, self.disk = synthetic(heads, sectors)
        self.source = image.open('rb') if image else None
        if image:
            self.capacity = image.stat().st_size//512
            self.disk = {}
        elif bad_bpb:
            self.disk[heads*sectors] = bytes(512)
        self.status = 0 if absent else 0x50
        self.absent, self.readonly = absent, readonly
        self.ports, self.commands = {}, []
        self.buffer = bytearray()
        self.word = 0
        self.handoff = False
        self.call_offset = 0
        self.chained = False
        self.u.hook_add(UC_HOOK_INSN, self.input, None, 1, 0, UC_X86_INS_IN)
        self.u.hook_add(UC_HOOK_INSN, self.output, None, 1, 0, UC_X86_INS_OUT)
        self.u.hook_add(UC_HOOK_INTR, self.interrupt)
        self.u.hook_add(UC_HOOK_CODE, self.code)
        self.u.hook_add(UC_HOOK_MEM_WRITE, self.nvram_write, None, 0xa3fe0, 0xa3fff)

    def nvram_write(self, u, access, address, size, value, _):
        raise AssertionError("Option ROM must not write protected NVRAM")

    def sector(self, lba):
        assert 0 <= lba < self.capacity, 'ATA read/write out of image range'
        if lba in self.disk:
            return self.disk[lba]
        if self.source:
            self.source.seek(lba*512)
            data = self.source.read(512)
            assert len(data)==512
            return data
        return bytes((lba+i)&255 for i in range(512))

    def output(self, u, port, size, value, _):
        self.ports[port] = value
        if port==0x64e:
            assert value in (0xec,0x20,0x30)
            self.command=value
            self.word=0
            if value==0xec:
                self.buffer=bytearray(512)
                struct.pack_into('<I',self.buffer,120,self.capacity)
                self.lba=None
            else:
                self.lba=(self.ports[0x646] | self.ports[0x648]<<8 |
                          self.ports[0x64a]<<16 | (self.ports[0x64c]&15)<<24)
                assert self.ports[0x644]==1 and self.ports[0x74c]==2
                self.buffer=bytearray(self.sector(self.lba))
            self.commands.append((value,self.lba))
            self.status=0x51 if value==0x30 and self.readonly else 0x58
        elif port==0x640:
            assert self.command==0x30 and self.status==0x58 and size==2
            struct.pack_into('<H',self.buffer,self.word*2,value)
            self.word+=1
            if self.word==256:
                self.disk[self.lba]=bytes(self.buffer)
                self.status=0x50

    def input(self,u,port,size,_):
        if port in (0x64e,0x74c):
            return self.status
        if port==0x640:
            assert self.status==0x58 and size==2
            result=struct.unpack_from('<H',self.buffer,self.word*2)[0]
            self.word+=1
            if self.word==256:self.status=0x50
            return result
        return self.ports.get(port,0xff)

    def interrupt(self,u,vector,_):
        if vector==0x18:
            return
        assert vector==0x1b
        flags=u.reg_read(UC_X86_REG_EFLAGS)
        ss,sp=u.reg_read(UC_X86_REG_SS),u.reg_read(UC_X86_REG_SP)
        for value in (flags,u.reg_read(UC_X86_REG_CS),u.reg_read(UC_X86_REG_IP)):
            sp=(sp-2)&65535
            u.mem_write(ss*16+sp,struct.pack('<H',value&65535))
        u.reg_write(UC_X86_REG_SP,sp)
        u.reg_write(UC_X86_REG_EFLAGS,flags&~0x300)
        ip,cs=struct.unpack('<HH',u.mem_read(vector*4,4))
        u.reg_write(UC_X86_REG_CS,cs)
        u.reg_write(UC_X86_REG_IP,ip)

    def code(self,u,address,size,_):
        if address==0x1fc00:
            self.handoff=True
            u.emu_stop()
        elif address==0xff282:
            self.chained=True
            u.emu_stop()

    def far_call(self,cs,ip,ax=0,bx=0):
        u=self.u
        code=b'\x9a'+struct.pack('<HH',ip,cs)+b'\xf4'
        offset=self.call_offset
        self.call_offset+=16
        u.mem_write(0x10000+offset,code)
        for reg,value in [(UC_X86_REG_CS,0x1000),(UC_X86_REG_IP,offset),
                          (UC_X86_REG_SS,0),(UC_X86_REG_SP,0x1800),
                          (UC_X86_REG_DS,0),(UC_X86_REG_AX,ax),(UC_X86_REG_BX,bx),
                          (UC_X86_REG_EFLAGS,0x602)]:u.reg_write(reg,value)
        u.emu_start(0x10000+offset,0x10006+offset,count=5000000)

    def initialize(self,owner_rom=None):
        if owner_rom:
            data=owner_rom.read_bytes()
            assert data[0x161f4:0x161fa]==bytes.fromhex('c706ac040c00')
            assert data[0x16228:0x1622e]==bytes.fromhex('c706ac040f00')
            self.u.mem_write(0xe8000,data[:0x18000])
            # These are near BIOS subroutines. Use same-CS trampolines in
            # otherwise unused emulated memory, preserving all original ROM.
            for slot,entry in [(0x7f00,0x9f4),(0x7f10,0xa28),(0x7f20,0xa30)]:
                self.u.mem_write(0xfd800+slot,b'\xe8'+struct.pack('<H',(entry-slot-3)&65535)+b'\xcb')
                self.far_call(0xfd80,slot)
        else:
            self.far_call(0xd000,0xc,bx=0x4d0)
            self.far_call(0xd000,0xf)
            self.far_call(0xd000,0x12)
        assert self.u.mem_read(0x4d0,1)==b'\xd9'
        assert self.u.reg_read(UC_X86_REG_CS)==0x1000
        assert self.u.reg_read(UC_X86_REG_SP)==0x1800
        assert self.u.reg_read(UC_X86_REG_EFLAGS)&0x600==0x600
        assert not any(cmd==0x30 for cmd,_ in self.commands), 'Initialization wrote to disk'
        # Built-in Z98MEM: 14 MB below 16 MB (128 KB units), 48 MB above it,
        # V30 flag cleared, every other identification bit preserved.
        assert self.u.mem_read(0x401,1)[0]==112, 'extended RAM below 16 MB not published'
        assert struct.unpack('<H',self.u.mem_read(0x594,2))[0]==48, 'RAM above 16 MB not published'
        assert self.u.mem_read(0x501,1)[0]==0x23, 'V30 flag not cleared or other bits changed'
        assert self.u.mem_read(0x54d,1)[0]==0x58, 'EGC-present bit 6 not set or other bits changed'
        return self.u.mem_read(0xd8008,1)[0]

    def owner_boot(self):
        # Exercise the system BIOS's actual boot dispatch as well as discovery.
        # Default automatic order starts at slot 1. The ROM claims that
        # pass for a valid HDD without changing the protected NVRAM.
        assert self.u.mem_read(0xa3ff2,1)[0]&0xf0==0
        slot,entry=0x7f30,0xa4b
        self.u.mem_write(0xfd800+slot,b'\xe8'+struct.pack('<H',(entry-slot-3)&65535)+b'\xcb')
        self.far_call(0xfd80,slot)

    def request(self,ax,bx,cx,dx,payload=None):
        u=self.u
        u.mem_write(0x11000,b'\xcd\x1b\xf4')
        u.mem_write(0x600, payload if payload is not None else bytes(512))
        for reg,value in [(UC_X86_REG_CS,0x1100),(UC_X86_REG_IP,0),
                          (UC_X86_REG_SS,0),(UC_X86_REG_SP,0x28e),
                          (UC_X86_REG_DS,0x1234),(UC_X86_REG_ES,0),
                          (UC_X86_REG_BP,0x600),(UC_X86_REG_AX,ax),
                          (UC_X86_REG_BX,bx),(UC_X86_REG_CX,cx),(UC_X86_REG_DX,dx),
                          (UC_X86_REG_EFLAGS,0x602)]:u.reg_write(reg,value)
        ivt=bytes(u.mem_read(0,512))
        u.emu_start(0x11000,0x11003,count=5000000)
        if not self.chained:
            assert bytes(u.mem_read(0,512))==ivt, 'Disk call corrupted the IVT'
            assert u.reg_read(UC_X86_REG_SP)==0x28e and u.reg_read(UC_X86_REG_SS)==0
            assert u.reg_read(UC_X86_REG_DS)==0x1234 and u.reg_read(UC_X86_REG_BP)==0x600
            assert u.reg_read(UC_X86_REG_EFLAGS)&0x600==0x600
        return u.reg_read(UC_X86_REG_AX),bool(u.reg_read(UC_X86_REG_EFLAGS)&1)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('rom',type=Path)
    p.add_argument('--image',type=Path)
    p.add_argument('--owner-rom',type=Path)
    a=p.parse_args()
    rom=a.rom.read_bytes()
    for heads,sectors in [(8,17),(8,32),(16,63),(16,32),(8,25),(4,17)]:
        m=Machine(rom,heads,sectors)
        assert m.initialize()==1
        ax,cf=m.request(0x8480,0,0,0)
        assert not cf and ax==0x0f80
        assert m.u.reg_read(UC_X86_REG_DX)==(heads<<8|sectors)
        assert m.u.reg_read(UC_X86_REG_CX)==1024
        assert m.request(0x0680,512,1,0)==(0x0080,False)
        assert bytes(m.u.mem_read(0x600,512))==m.sector(heads*sectors)
        m.far_call(0xd000,0x15,ax=0x0a)
        assert m.handoff and m.u.mem_read(0x584,1)==b'\x80'
        assert bytes(m.u.mem_read(0x1fc00,1024))==m.sector(0)+m.sector(1)
        print('PASS: native ROM init/geometry/CHS/tiny stack/IPL',heads,sectors)
    # PC-98 DOS logical sectors can span several physical 512-byte ATA
    # sectors. Older NEC BPBs encode hidden LBA/physical bytes differently.
    for logical in (512,1024,2048):
        for legacy in (False,True):
            m=Machine(rom,4,17)
            start=4*17
            bpb=bytearray(m.disk[start])
            struct.pack_into('<H',bpb,11,logical)
            total=min((m.capacity-start)//(logical//512),60000)
            struct.pack_into('<H',bpb,19,total)
            struct.pack_into('<I',bpb,32,0)
            if legacy:
                struct.pack_into('<I',bpb,24,start)
                struct.pack_into('<HH',bpb,28,50,512)
                bpb[32:36]=bytes.fromhex('0033c08e')
            m.disk[start]=bytes(bpb)
            assert m.initialize()==1, (logical,legacy)
            ax,cf=m.request(0x8480,0,0,0)
            assert not cf and m.u.reg_read(UC_X86_REG_BX)==512
            assert m.u.reg_read(UC_X86_REG_DX)==0x0411
            assert m.request(0x0680,logical,1,0)==(0x0080,False)
            expected=b''.join(m.sector(start+i) for i in range(logical//512))
            assert bytes(m.u.mem_read(0x600,logical))==expected
            print('PASS: DOS logical/ATA physical sector geometry',logical,legacy)
    for kind in ('unsupported-logical','oversized-volume','legacy-physical','legacy-hidden'):
        m=Machine(rom,4,17)
        start=68
        bpb=bytearray(m.disk[start])
        struct.pack_into('<H',bpb,11,1024)
        if kind=='unsupported-logical':struct.pack_into('<H',bpb,11,4096)
        if kind=='oversized-volume':struct.pack_into('<I',bpb,32,0xffffffff)
        if kind.startswith('legacy-'):
            struct.pack_into('<H',bpb,19,30000)
            struct.pack_into('<I',bpb,24,start+(kind=='legacy-hidden'))
            struct.pack_into('<HH',bpb,28,50,256 if kind=='legacy-physical' else 512)
        m.disk[start]=bytes(bpb)
        assert m.initialize()==4, kind
        assert m.u.mem_read(0x6c,4)==m.original_vector
        assert not any(cmd==0x30 for cmd,_ in m.commands)
        print('PASS: rejected invalid logical-sector BPB',kind)
    m=Machine(rom)
    assert m.initialize()==1
    before=m.sector(17)
    data=bytes(range(31))
    assert m.request(0x0500,31,17,0,data)==(0,False)
    assert m.sector(17)==data+before[31:]
    n=len(m.commands)
    assert m.request(0x0500,512,m.capacity&65535,m.capacity>>16)[1]
    assert len(m.commands)==n, 'Out-of-range request reached ATA'
    m.request(0x0690,512,0,0)
    assert m.chained, 'Floppy did not retain the previous BIOS'
    print('PASS: bounded partial writes, untouched sector tail, image bounds, floppy chaining')
    for options,state in [({'absent':True},2),({'bad_bpb':True},4)]:
        m=Machine(rom,**options)
        assert m.initialize()==state
        assert m.u.mem_read(0x6c,4)==m.original_vector
        m.far_call(0xd000,0x15,ax=0x0a)
        assert not m.handoff
        print('PASS: rejected image without installing a disk handler',options)
    m=Machine(rom,readonly=True)
    assert m.initialize()==1
    assert m.request(0x0500,512,17,0,bytes(512))[1]
    assert 17 not in m.disk
    print('PASS: read-only ATA image rejects writes')
    for priority,options,boot_slot,expected in [
            (0x01,{},1,True), (0x01,{},2,False),
            (0x11,{},1,False), (0x21,{},1,False),
            (0xa1,{},0xa,True), (0x21,{},0xa,True),
            (0x01,{'absent':True},1,False),
            (0x01,{'bad_bpb':True},1,False)]:
        m=Machine(rom,**options)
        m.u.mem_write(0xa3ff2,bytes([priority]))
        m.initialize()
        m.far_call(0xd000,0x15,ax=boot_slot)
        assert m.handoff==expected, (priority, options, boot_slot)
        assert m.u.mem_read(0xa3ff2,1)==bytes([priority])
    print('PASS: automatic HDD boot, explicit boot priority, absent/invalid media, no NVRAM writes')
    if a.image:
        m=Machine(rom,image=a.image)
        assert m.initialize(a.owner_rom)==1
        if a.owner_rom:
            m.owner_boot()
        else:
            m.far_call(0xd000,0x15,ax=0xa)
        assert m.handoff
        assert bytes(m.u.mem_read(0x1fc00,1024))==m.sector(0)+m.sector(1)
        print('PASS: owner image IPL; system-ROM discovery' if a.owner_rom else 'PASS: owner image IPL')
