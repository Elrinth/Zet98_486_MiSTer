"""Independent DOS/XMS protocol model; production probe executes actual PM CRC.
No original WAD or private code needed. CRC oracle is Python zlib.
"""
from pathlib import Path
import json, struct, sys, zlib
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'build/verification-python'))
from unicorn import *
from unicorn.x86_const import *

def run(binary, case):
    size = {'minimum':12, 'even':65536, 'boundary':32769}.get(case,98323)
    data = bytes((i*37+(i>>8)+(i>>16))&255 for i in range(size))
    u=Uc(UC_ARCH_X86, UC_MODE_16); u.mem_map(0,0x400000)
    u.mem_write(0x20100,binary); u.mem_write(0x20002,b'\x00\x90')
    u.mem_write(0xf0100,b'\xcd\xe6\xcb')
    for r in (UC_X86_REG_CS,UC_X86_REG_DS,UC_X86_REG_ES,UC_X86_REG_SS): u.reg_write(r,0x2000)
    u.reg_write(UC_X86_REG_SP,0xfffe);u.reg_write(UC_X86_REG_CR0,0x10)
    u.reg_write(UC_X86_REG_EFLAGS,0x602 if case=='df_set' else 0x202)
    u.reg_write(UC_X86_REG_GDTR,(0,0x500,0x3f,0));u.reg_write(UC_X86_REG_IDTR,(0,0,0x3ff,0))
    u.reg_write(UC_X86_REG_FS,0x1234);u.reg_write(UC_X86_REG_GS,0x4321)
    s=dict(pos=0,exit=None,result=b'',allocated=False,locked=False,a20=False,reads=0,moves=0,restored=False)
    def intr(uc,num,_):
        assert not uc.reg_read(UC_X86_REG_CR0)&1, ('exception or DOS in PM',num,hex(uc.reg_read(UC_X86_REG_EIP)))
        ax,bx,cx,dx=[uc.reg_read(r) for r in (UC_X86_REG_AX,UC_X86_REG_BX,UC_X86_REG_CX,UC_X86_REG_DX)]
        ah=ax>>8; ptr=uc.reg_read(UC_X86_REG_DS)*16+dx
        def error(): uc.reg_write(UC_X86_REG_EFLAGS,uc.reg_read(UC_X86_REG_EFLAGS)|1)
        uc.reg_write(UC_X86_REG_EFLAGS,uc.reg_read(UC_X86_REG_EFLAGS)&~1)
        if num==0x2f:
            if ax==0x4300: uc.reg_write(UC_X86_REG_AL,0 if case=='no_xms' else 0x80)
            elif ax==0x4310: uc.reg_write(UC_X86_REG_ES,0xf000);uc.reg_write(UC_X86_REG_BX,0x100)
            else: raise AssertionError(hex(ax))
            return
        if num==0xe6:
            uc.reg_write(UC_X86_REG_AX,1)
            if ah==9:
                assert dx==(len(data)+1023)//1024
                if case=='alloc_error':uc.reg_write(UC_X86_REG_AX,0);return
                s['allocated']=True;uc.reg_write(UC_X86_REG_DX,1)
            elif ah==0xb:
                assert s['allocated'];s['moves']+=1
                desc=bytes(uc.mem_read(uc.reg_read(UC_X86_REG_DS)*16+uc.reg_read(UC_X86_REG_SI),16))
                count,src,so,dst,do=struct.unpack('<IHIHI',desc)
                assert src==0 and dst==1 and count%2==0 and 0<count<=32768
                assert do+count<=((len(data)+1023)//1024)*1024
                if case=='move_error':uc.reg_write(UC_X86_REG_AX,0);return
                source=(so>>16)*16+(so&65535)
                uc.mem_write(0x110000+do,bytes(uc.mem_read(source,count)))
            elif ah==0xc:
                assert s['allocated'] and dx==1
                if case=='lock_error':uc.reg_write(UC_X86_REG_AX,0);return
                s['locked']=True;uc.reg_write(UC_X86_REG_DX,0x11);uc.reg_write(UC_X86_REG_BX,0)
                if case=='corrupt':uc.mem_write(0x118003,bytes([data[0x8003]^1]))
            elif ah==5:
                if case=='a20_error':uc.reg_write(UC_X86_REG_AX,0);return
                assert s['locked'];s['a20']=True
            elif ah==6:assert s['a20'];s['a20']=False
            elif ah==0xd:assert s['locked'];s['locked']=False
            elif ah==0xa:assert s['allocated'] and not s['locked'];s['allocated']=False
            else:raise AssertionError(('XMS',ah))
            return
        assert num==0x21, num
        if ah==0x35:uc.reg_write(UC_X86_REG_ES,0xf000);uc.reg_write(UC_X86_REG_BX,0x2400)
        elif ah==0x25:
            if uc.reg_read(UC_X86_REG_DS)==0xf000:assert dx==0x2400;s['restored']=True
        elif ah==0x5b:
            assert bytes(uc.mem_read(ptr,32)).split(b'\0')[0]==b'A:\\WADPM.BIN'
            if case=='existing':error()
            else:uc.reg_write(UC_X86_REG_AX,8)
        elif ah==0x3d:
            assert ax==0x3d00 and bytes(uc.mem_read(ptr,32)).split(b'\0')[0]==b'A:\\DOOM1\\DOOM.WAD'
            if case=='open_error':error()
            else:uc.reg_write(UC_X86_REG_AX,7)
        elif ah==0x42:
            assert bx==7 and cx==dx==0
            if case=='seek_error':error();return
            s['pos']=(0x2000001 if case=='too_large' else len(data)) if ax&255==2 else 0
            uc.reg_write(UC_X86_REG_AX,s['pos']&65535);uc.reg_write(UC_X86_REG_DX,s['pos']>>16)
        elif ah==0x3f:
            assert bx==7 and 0<cx<=32768 and dx==0x4000;s['reads']+=1
            if case=='read_error':error();return
            chunk=data[s['pos']:s['pos']+cx]
            if case=='short_read':chunk=chunk[:-1]
            if case=='growth' and s['pos']==len(data):chunk=b'!'
            if chunk:uc.mem_write(ptr,chunk)
            s['pos']+=len(chunk);uc.reg_write(UC_X86_REG_AX,len(chunk))
        elif ah==0x40:
            assert bx==8
            s['result']=bytes(uc.mem_read(ptr,cx-1 if case=='short_write' else cx))
            uc.reg_write(UC_X86_REG_AX,len(s['result']))
        elif ah==0x3e:assert bx in (7,8)
        elif ah==9:pass
        elif ah==0x4c:s['exit']=ax&255;uc.emu_stop()
        else:raise AssertionError(hex(ax))
    u.hook_add(UC_HOOK_INTR,intr)
    u.emu_start(0x20100,0,count=6000000)
    good=case in ('normal','minimum','even','boundary','df_set','corrupt')
    assert s['exit']==(0 if good else 1),(case,s)
    assert not any(s[x] for x in ('allocated','locked','a20')) and s['restored'],case
    assert u.reg_read(UC_X86_REG_CR0)==0x10 and u.reg_read(UC_X86_REG_CS)==0x2000
    assert u.reg_read(UC_X86_REG_SS)==0x2000 and u.reg_read(UC_X86_REG_SP)==0xfffe
    assert u.reg_read(UC_X86_REG_FS)==0x1234 and u.reg_read(UC_X86_REG_GS)==0x4321
    assert u.reg_read(UC_X86_REG_GDTR)[1:3]==(0x500,0x3f) and u.reg_read(UC_X86_REG_IDTR)[1:3]==(0,0x3ff)
    if good:
        r=s['result'];count=(len(data)+32767)//32768
        assert r[:8]==b'Z98PMRD1' and len(r)==64+4*count
        assert struct.unpack_from('<6I',r,8)==(0,len(data),len(data),0x110000,len(data),count)
        checks=list(struct.unpack_from('<%dI'%count,r,64))
        expected=[zlib.crc32(data[:min((i+1)*32768,len(data))]) for i in range(count)]
        if case=='corrupt':assert checks[0]==expected[0] and checks[1:]!=expected[1:]
        else:assert checks==expected,(checks,expected)
    return dict(case=case,passed=True,reads=s['reads'],moves=s['moves'])

if __name__=='__main__':
    cases=['normal','minimum','even','boundary','df_set','corrupt','existing','no_xms','open_error','seek_error',
           'too_large','alloc_error','read_error','short_read','move_error','growth','lock_error','a20_error','short_write']
    print(json.dumps(dict(passed=True,cases=[run(Path(sys.argv[1]).read_bytes(),c) for c in cases]),indent=2))
