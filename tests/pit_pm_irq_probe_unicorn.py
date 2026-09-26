"""Test PM probe mode transitions/IRQ frames/cleanup with a modeled PIC.

Shorten only its busy-wait ECX in the model; actual hardware binary retains
five million iterations. This is not proof of FPGA interrupt delivery.
"""
from pathlib import Path
import sys,struct,json
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'build/verification-python'))
from unicorn import *
from unicorn.x86_const import *

def run(binary,case):
    u=Uc(UC_ARCH_X86,UC_MODE_16);u.mem_map(0,0x100000);u.mem_write(0x20100,binary)
    for r,v in [(UC_X86_REG_CS,0x2000),(UC_X86_REG_DS,0x2000),(UC_X86_REG_ES,0x2000),(UC_X86_REG_SS,0x2000),(UC_X86_REG_SP,0xfffe),(UC_X86_REG_EFLAGS,0x202),(UC_X86_REG_CR0,0x10)]:u.reg_write(r,v)
    u.reg_write(UC_X86_REG_GDTR,(0,0x500,0x3f,0));u.reg_write(UC_X86_REG_IDTR,(0,0,0x3ff,0))
    s=dict(mask=0xfc,irqs=0,eoi=0,instructions=0,shortened=False,exits=[],output=[],pit=[],control=[],fault=False)
    def out(uc,port,size,value,_):
        assert size==1
        if port==2:s['mask']=value
        elif port==0:assert value==0x20;s['eoi']+=1
        elif port==0x77:s['control'].append(value)
        elif port==0x71:s['pit'].append(value)
        else:raise AssertionError(port)
    def inp(uc,port,size,_):assert port==2 and size==1;return s['mask']
    def intr(uc,n,_):
        assert n==0x21, ('unexpected exception',n,hex(uc.reg_read(UC_X86_REG_EIP)))
        assert uc.reg_read(UC_X86_REG_CR0)==0x10, 'DOS called before leaving protected mode'
        fn=uc.reg_read(UC_X86_REG_AH)
        if fn==9:
            a=uc.reg_read(UC_X86_REG_DS)*16+uc.reg_read(UC_X86_REG_DX);s['output'].append(bytes(uc.mem_read(a,256)).split(b'$')[0].decode())
        elif fn==2:s['output'].append(chr(uc.reg_read(UC_X86_REG_DL)))
        elif fn==0x4c:s['exits'].append(uc.reg_read(UC_X86_REG_AL));uc.emu_stop()
        else:raise AssertionError(fn)
    def code(uc,address,size,_):
        if not uc.reg_read(UC_X86_REG_CR0)&1:return
        if not s['shortened'] and bytes(uc.mem_read(address,1))==b'\xfb':
            assert uc.reg_read(UC_X86_REG_ECX)==5000000
            uc.reg_write(UC_X86_REG_ECX,20000);s['shortened']=True
        s['instructions']+=1
        if s['mask']&1 or not uc.reg_read(UC_X86_REG_EFLAGS)&0x200:return
        if case=='no_interrupts' or (case=='interrupts' and s['instructions']%1000):return
        vector=13 if case=='exception' else 8
        base=uc.reg_read(UC_X86_REG_IDTR)[1];gate=bytes(uc.mem_read(base+vector*8,8))
        lo,cs,attrs,hi=struct.unpack('<HHHH',gate);assert attrs==0x8e00 and cs==8
        flags=uc.reg_read(UC_X86_REG_EFLAGS);sp=uc.reg_read(UC_X86_REG_ESP)
        for value in (flags,uc.reg_read(UC_X86_REG_CS),uc.reg_read(UC_X86_REG_EIP)):
            sp-=4;uc.mem_write(0x20000+sp,struct.pack('<I',value))
        if vector==13:sp-=4;uc.mem_write(0x20000+sp,b'\0'*4);s['fault']=True
        else:s['irqs']+=1
        uc.reg_write(UC_X86_REG_ESP,sp);uc.reg_write(UC_X86_REG_EFLAGS,flags&~0x300)
        uc.reg_write(UC_X86_REG_CS,cs);uc.reg_write(UC_X86_REG_EIP,lo|(hi<<16))
    u.hook_add(UC_HOOK_INTR,intr);u.hook_add(UC_HOOK_CODE,code)
    u.hook_add(UC_HOOK_INSN,inp,None,1,0,UC_X86_INS_IN);u.hook_add(UC_HOOK_INSN,out,None,1,0,UC_X86_INS_OUT)
    u.emu_start(0x20100,0,count=200000)
    assert s['exits']==[0 if case=='interrupts' else 1],s
    assert u.reg_read(UC_X86_REG_CR0)==0x10 and u.reg_read(UC_X86_REG_CS)==0x2000
    assert u.reg_read(UC_X86_REG_SS)==0x2000 and u.reg_read(UC_X86_REG_SP)==0xfffe
    assert u.reg_read(UC_X86_REG_GDTR)[1:3]==(0x500,0x3f) and u.reg_read(UC_X86_REG_IDTR)[1:3]==(0,0x3ff)
    assert s['mask']==0xfc and s['control']==[0x36,0x36] and s['pit']==[17554&255,17554>>8,0,0x60]
    assert s['eoi']==s['irqs']+1 and u.reg_read(UC_X86_REG_EFLAGS)&0x200
    return dict(case=case,irqs=s['irqs'],fault=s['fault'],output=''.join(s['output']),exit=s['exits'][0])
if __name__=='__main__':
    b=Path(sys.argv[1]).read_bytes();print(json.dumps(dict(passed=True,cases=[run(b,c) for c in ['interrupts','no_interrupts','exception']]),indent=2))
