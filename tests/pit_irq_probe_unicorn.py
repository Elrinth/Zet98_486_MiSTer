"""Protocol checks for self-authored DOS IRQ probe, not hardware IRQ evidence."""
from pathlib import Path
import sys,struct,json
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'build/verification-python'))
from unicorn import *
from unicorn.x86_const import *

def run(binary,case):
    u=Uc(UC_ARCH_X86,UC_MODE_16);u.mem_map(0,0x100000)
    u.mem_write(0x20100,binary);original=struct.pack('<HH',0x1234,0xf000);u.mem_write(32,original)
    for r,v in [(UC_X86_REG_CS,0x2000),(UC_X86_REG_DS,0x2000),(UC_X86_REG_ES,0x2000),(UC_X86_REG_SS,0x2000),(UC_X86_REG_SP,0xfffe),(UC_X86_REG_EFLAGS,0x202)]:u.reg_write(r,v)
    s=dict(mask=0xfc,rtc=0,instructions=0,irqs=0,eoi=0,exits=[],output=[],pit=[],control=[])
    def out(uc,port,size,value,_):
        assert size==1
        if port==2:s['mask']=value
        elif port==0:assert value==0x20;s['eoi']+=1
        elif port==0x77:s['control'].append(value)
        elif port==0x71:s['pit'].append(value)
        else:raise AssertionError(port)
    def inp(uc,port,size,_):assert port==2 and size==1;return s['mask']
    def intr(uc,n,_):
        if n==0x1c:
            assert uc.reg_read(UC_X86_REG_AH)==0
            s['rtc']+=1;second=(s['rtc']//5)%60
            if case=='invalid_clock':second=0xfa
            else:second=(second//10)*16+second%10
            a=uc.reg_read(UC_X86_REG_ES)*16+uc.reg_read(UC_X86_REG_BX)
            uc.mem_write(a,bytes([0x26,0x90,0x25,1,0,second]));return
        assert n==0x21
        fn=uc.reg_read(UC_X86_REG_AH)
        if fn==0x35:
            assert uc.reg_read(UC_X86_REG_AL)==8
            ip,cs=struct.unpack('<HH',bytes(uc.mem_read(32,4)));uc.reg_write(UC_X86_REG_BX,ip);uc.reg_write(UC_X86_REG_ES,cs)
        elif fn==0x25:
            assert uc.reg_read(UC_X86_REG_AL)==8
            uc.mem_write(32,struct.pack('<HH',uc.reg_read(UC_X86_REG_DX),uc.reg_read(UC_X86_REG_DS)))
        elif fn==9:
            a=uc.reg_read(UC_X86_REG_DS)*16+uc.reg_read(UC_X86_REG_DX)
            s['output'].append(bytes(uc.mem_read(a,256)).split(b'$')[0].decode())
        elif fn==2:s['output'].append(chr(uc.reg_read(UC_X86_REG_DL)))
        elif fn==0x4c:s['exits'].append(uc.reg_read(UC_X86_REG_AL));uc.emu_stop()
        else:raise AssertionError(fn)
    def code(uc,address,size,_):
        s['instructions']+=1
        if case!='interrupts' or s['instructions']%3000 or s['mask']&1 or not uc.reg_read(UC_X86_REG_EFLAGS)&0x200:return
        vector=bytes(uc.mem_read(32,4))
        if vector==original:return
        flags=uc.reg_read(UC_X86_REG_EFLAGS);sp=uc.reg_read(UC_X86_REG_SP);ss=uc.reg_read(UC_X86_REG_SS)
        for value in (flags&0xffff,uc.reg_read(UC_X86_REG_CS),uc.reg_read(UC_X86_REG_IP)):
            sp=(sp-2)&0xffff;uc.mem_write(ss*16+sp,struct.pack('<H',value))
        ip,cs=struct.unpack('<HH',vector)
        uc.reg_write(UC_X86_REG_SP,sp);uc.reg_write(UC_X86_REG_EFLAGS,flags&~0x300);uc.reg_write(UC_X86_REG_CS,cs);uc.reg_write(UC_X86_REG_IP,ip);s['irqs']+=1
    u.hook_add(UC_HOOK_INTR,intr);u.hook_add(UC_HOOK_CODE,code)
    u.hook_add(UC_HOOK_INSN,inp,None,1,0,UC_X86_INS_IN);u.hook_add(UC_HOOK_INSN,out,None,1,0,UC_X86_INS_OUT)
    u.emu_start(0x20100,0,count=2000000)
    assert s['exits']==[0 if case=='interrupts' else 1],s
    assert bytes(u.mem_read(32,4))==original and s['mask']==0xfc
    assert s['control']==[0x36,0x36] and s['pit']==[17554&255,17554>>8,0,0x60]
    assert s['eoi']==s['irqs']+1 and u.reg_read(UC_X86_REG_EFLAGS)&0x200
    output=''.join(s['output']);assert '%04X'%s['irqs'] in output
    return dict(case=case,irqs=s['irqs'],output=output,exit=s['exits'][0])
if __name__=='__main__':
    binary=Path(sys.argv[1]).read_bytes()
    print(json.dumps(dict(passed=True,cases=[run(binary,c) for c in ['interrupts','no_interrupts','invalid_clock']]),indent=2))
