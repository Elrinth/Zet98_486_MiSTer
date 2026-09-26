"""Run the actual self-authored DOS probe; verify BIOS reads and flag reporting."""
from pathlib import Path
import json
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'build/verification-python'))
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UC_HOOK_MEM_WRITE
from unicorn.x86_const import *


def run(program, identity, flag0, flag1, initial_flags):
    u = Uc(UC_ARCH_X86, UC_MODE_16)
    u.mem_map(0, 0x100000)
    u.mem_write(0x20100, program)
    u.mem_write(0x480, bytes([identity]))
    u.mem_write(0x500, bytes([flag0, flag1]))
    before = bytes(u.mem_read(0, 0x1000))
    for reg, value in [(UC_X86_REG_CS,0x2000),(UC_X86_REG_DS,0x2000),
                       (UC_X86_REG_ES,0x2000),(UC_X86_REG_SS,0x2000),
                       (UC_X86_REG_SP,0xfffe),(UC_X86_REG_EFLAGS,initial_flags)]:
        u.reg_write(reg,value)
    output=[];exit_codes=[]

    def interrupt(uc,n,_):
        assert n==0x21
        assert uc.reg_read(UC_X86_REG_EFLAGS)&0x200, 'IF not restored before DOS'
        fn=uc.reg_read(UC_X86_REG_AH)
        if fn==9:
            a=uc.reg_read(UC_X86_REG_DS)*16+uc.reg_read(UC_X86_REG_DX)
            output.append(bytes(uc.mem_read(a,256)).split(b'$',1)[0].decode())
        elif fn==2:
            output.append(chr(uc.reg_read(UC_X86_REG_DL)))
        else:
            assert fn==0x4c
            exit_codes.append(uc.reg_read(UC_X86_REG_AL));uc.emu_stop()

    def low_write(uc,access,address,size,value,_):
        raise AssertionError('Probe attempted to modify BIOS/IVT memory')

    u.hook_add(UC_HOOK_INTR,interrupt)
    u.hook_add(UC_HOOK_MEM_WRITE,low_write,begin=0,end=0xfff)
    u.emu_start(0x20100,0,count=50000)
    assert exit_codes==[0]
    text=''.join(output)
    assert 'FLAGS after POPF(0) = 0002' in text
    for address,value in [(0x480,identity),(0x500,flag0),(0x501,flag1)]:
        assert 'BIOS 0000:%04X = %04X' % (address,value) in text
    assert '8086 FLAGS rejection = 0000' in text
    assert 'BIOS bit40 rejection = %04X' % ((flag1>>6)&1) in text
    assert bytes(u.mem_read(0,0x1000))==before
    return dict(identity=identity,flag0=flag0,flag1=flag1,output=text)


if __name__=='__main__':
    program=Path(sys.argv[1]).read_bytes()
    results=[run(program,*case,flags) for flags in (0x202,0x602) for case in [(0,1,0x60),(1,1,0x20),(3,1,0x20),(3,0xff,0xe7)]]
    print(json.dumps(dict(passed=True,cases=results),indent=2))
