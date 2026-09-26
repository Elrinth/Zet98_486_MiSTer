#!/usr/bin/env python3
"""Validate the DOS flag probe and its failure path before hardware use."""
from pathlib import Path
import struct
import sys
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_CODE
from unicorn.x86_const import *


def run(binary, corrupt=False):
    uc=Uc(UC_ARCH_X86, UC_MODE_16)
    uc.mem_map(0, 2*1024*1024)
    base=0x20000
    uc.mem_write(base+0x100,binary)
    for register in (UC_X86_REG_CS,UC_X86_REG_DS,UC_X86_REG_ES,UC_X86_REG_SS):
        uc.reg_write(register,base>>4)
    uc.reg_write(UC_X86_REG_SP,0xff00)
    uc.reg_write(UC_X86_REG_EFLAGS,0x202)
    output=[]; saved=[]; injected=False; traps=[]

    def clear_carry():
        uc.reg_write(UC_X86_REG_EFLAGS,uc.reg_read(UC_X86_REG_EFLAGS)&~1)

    def interrupt(machine, number, unused):
        if number==1:
            flags=uc.reg_read(UC_X86_REG_EFLAGS)
            cs=uc.reg_read(UC_X86_REG_CS); ip=uc.reg_read(UC_X86_REG_IP)
            traps.append(ip)
            sp=(uc.reg_read(UC_X86_REG_SP)-6)&0xffff
            uc.mem_write((uc.reg_read(UC_X86_REG_SS)<<4)+sp,struct.pack('<HHH',ip,cs,flags&0xffff))
            uc.reg_write(UC_X86_REG_SP,sp)
            uc.reg_write(UC_X86_REG_EFLAGS,flags&~0x300)
            target,segment=struct.unpack('<HH',uc.mem_read(4,4))
            uc.reg_write(UC_X86_REG_CS,segment);uc.reg_write(UC_X86_REG_IP,target)
            return
        assert number==0x21, 'Unexpected emulated interrupt %02x'%number
        ax=uc.reg_read(UC_X86_REG_AX);ah=ax>>8
        pointer=(uc.reg_read(UC_X86_REG_DS)<<4)+uc.reg_read(UC_X86_REG_DX)
        if ah==0x35:
            offset,segment=struct.unpack('<HH',uc.mem_read((ax&255)*4,4))
            uc.reg_write(UC_X86_REG_BX,offset);uc.reg_write(UC_X86_REG_ES,segment)
        elif ah==0x25:
            uc.mem_write((ax&255)*4,struct.pack('<HH',uc.reg_read(UC_X86_REG_DX),uc.reg_read(UC_X86_REG_DS)))
        elif ah==9:
            data=bytes(uc.mem_read(pointer,512)).split(b'$')[0]
            output.append(data.decode('ascii'))
        elif ah==0x5b:
            assert bytes(uc.mem_read(pointer,64)).split(b'\0')[0]==b'A:\\Z98FLAGS.TXT'
            assert not saved
            uc.reg_write(UC_X86_REG_AX,0x42)
        elif ah==0x40:
            assert uc.reg_read(UC_X86_REG_BX)==0x42
            length=uc.reg_read(UC_X86_REG_CX)
            saved.append(bytes(uc.mem_read(pointer,length)))
            uc.reg_write(UC_X86_REG_AX,length)
        elif ah not in (0x3e,0x0d):
            raise AssertionError('Unexpected DOS function %04x'%ax)
        clear_carry()

    def instruction(machine,address,size,unused):
        nonlocal injected
        opcode=bytes(uc.mem_read(address,size))
        if corrupt and not injected and opcode==b'\x9c':
            uc.reg_write(UC_X86_REG_EFLAGS,uc.reg_read(UC_X86_REG_EFLAGS)^1)
            injected=True
        if opcode==b'\xf4':uc.emu_stop()

    uc.hook_add(UC_HOOK_INTR,interrupt)
    uc.hook_add(UC_HOOK_CODE,instruction)
    uc.emu_start(base+0x100,base+0x100+len(binary),count=1000000)
    assert len(saved)==1, 'No saved result: '+repr(output)
    if corrupt:
        assert injected and b'FAIL stage=1 traps=0000' in saved[0],saved
        assert not traps
    else:
        assert b'PASS stage=4 traps=0001' in saved[0],saved
        assert len(traps)==1,traps
    print(('PASS injected-error rejection: ' if corrupt else 'PASS emulator: ')+saved[0].decode().strip())


if __name__=='__main__':
    binary=Path(sys.argv[1]).read_bytes()
    run(binary)
    run(binary,True)
