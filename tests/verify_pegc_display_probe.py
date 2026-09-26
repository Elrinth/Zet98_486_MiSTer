"""Execute the self-authored DOS probe; compare memory to an independent raster."""
from pathlib import Path
import sys
from unicorn import Uc,UC_ARCH_X86,UC_MODE_16,UC_HOOK_INTR,UC_HOOK_INSN,UC_HOOK_MEM_WRITE,UC_HOOK_CODE
from unicorn.x86_const import *

binary=Path(sys.argv[1]).read_bytes()
bios9821='--bios9821' in sys.argv[2:]
pitch_only='--pitch-only' in sys.argv[2:]
staged='--staged' in sys.argv[2:]
reference=bytes(((i//640)^((i%640)//8))&255 for i in range(262144))

def verify(corrupt=False):
    u=Uc(UC_ARCH_X86,UC_MODE_16);u.mem_map(0,0x100000)
    u.mem_write(0x10100,binary);u.mem_write(0x10002,b'\x00\x90')
    for r in (UC_X86_REG_CS,UC_X86_REG_DS,UC_X86_REG_ES,UC_X86_REG_SS):u.reg_write(r,0x1000)
    u.reg_write(UC_X86_REG_SP,0xfffe)
    backing=bytearray(262144)
    state=dict(bank=0,selects=[],ports=[],messages=[],result=b'',halt=False,bios=[])
    def output(uc,port,size,value,_):state['ports'].append((port,value))
    def write(uc,access,address,size,value,_):
        if address==0xe0004:
            assert size==1 and value<8
            state['bank']=value;state['selects'].append(value)
            data=bytearray(backing[value*32768:(value+1)*32768])
            if corrupt and len(state['selects'])==9:data[0]^=1
            uc.mem_write(0xa8000,bytes(data))
        elif 0xa8000<=address<0xb0000:
            assert size==1
            backing[state['bank']*32768+address-0xa8000]=value
    def interrupt(uc,number,_):
        ax=uc.reg_read(UC_X86_REG_AX);ah=ax>>8
        if number==0x18:
            state['bios'].append((ax,uc.reg_read(UC_X86_REG_BX),uc.reg_read(UC_X86_REG_CX)))
            if ah==0x31:uc.reg_write(UC_X86_REG_AX,0x3108)
            return
        assert number==0x21,number
        pointer=uc.reg_read(UC_X86_REG_DS)*16+uc.reg_read(UC_X86_REG_DX)
        if ah==9:state['messages'].append(bytes(uc.mem_read(pointer,160)).split(b'$')[0])
        elif ah==0x5b:
            expected_name=b'A:\\Z98PGC.TXT\0'
            assert bytes(uc.mem_read(pointer,len(expected_name)))==expected_name
            uc.reg_write(UC_X86_REG_AX,5)
        elif ah==0x40:
            count=uc.reg_read(UC_X86_REG_CX)
            state['result']+=bytes(uc.mem_read(pointer,count));uc.reg_write(UC_X86_REG_AX,count)
        else:assert ah in ((0x3e,0x0d,2,8) if staged else (0x3e,0x0d)),hex(ax)
        uc.reg_write(UC_X86_REG_EFLAGS,uc.reg_read(UC_X86_REG_EFLAGS)&~1)
    def halt(uc,address,size,_):state['halt']=True;uc.emu_stop()
    u.hook_add(UC_HOOK_INTR,interrupt)
    u.hook_add(UC_HOOK_INSN,lambda *args:0,None,1,0,UC_X86_INS_IN)
    u.hook_add(UC_HOOK_INSN,output,None,1,0,UC_X86_INS_OUT)
    u.hook_add(UC_HOOK_MEM_WRITE,write)
    for i in range(len(binary)-2):
        if binary[i:i+3]==b'\xf4\xeb\xfd':u.hook_add(UC_HOOK_CODE,halt,None,0x10100+i,0x10100+i)
    u.emu_start(0x10100,0xfffff,count=20000000)
    assert state['halt'],'probe did not terminate at its display wait'
    assert bytes(backing)==reference,'independent framebuffer pattern mismatch'
    if corrupt:
        assert state['messages'][-1].startswith(b'FAIL:') and not state['result']
        print('PASS: readback corruption rejected')
        return
    assert state['selects']==list(range(8))*2
    assert state['result'].startswith(b'PASS: all 262144')
    if bios9821:
        assert [v[0]>>8 for v in state['bios']]==[0x31,0x30,0x4d,0x0c,0x40],state['bios']
        assert state['bios'][1][0]==0x3008 and state['bios'][1][1]>>8==0x11
        assert state['bios'][2][2]>>8==1
    else:
        assert [v[0] for v in state['bios']]==[0x4200,0x0c0d],state['bios']
    palette=[(p,v) for p,v in state['ports'] if p in (0xa8,0xaa,0xac,0xae)]
    assert palette==[(p,v) for i in range(256) for p,v in ((0xa8,i),(0xac,i),(0xaa,255-i),(0xae,i^0x55))]
    gdc=[(p,v) for p,v in state['ports'] if p in (0xa0,0xa2)]
    if bios9821:
        sequence=[(0xa2,0x47),(0xa0,40),(0xa2,0x4b)]+[(0xa0,0)]*3+[(0xa2,0x70)]+[(0xa0,v) for v in (0,0,0,25,0,0,0,0)]+[(0xa2,0x0d)]
        assert gdc==(sequence if staged else [(0xa2,0x47),(0xa0,40)] if pitch_only else []),'Unexpected geometry changes'
        assert [(p,v) for p,v in state['ports'] if p==0x6a and v in (0x82,0x84)]==([(0x6a,0x82),(0x6a,0x84)] if staged else [])
    else:
        assert gdc==[(0xa2,0x47),(0xa0,40),(0xa2,0x4b)]+[(0xa0,0)]*3+[(0xa2,0x70)]+[(0xa0,v) for v in (0,0,0,25,0,0,0,0)]+[(0xa2,0x0d)],gdc
    print('PASS: 262144 independent pixels, palette, readback and '+('staged geometry controls' if staged else 'extended BIOS calls; pitch-only control' if pitch_only else 'extended BIOS calls without geometry repair' if bios9821 else 'explicit raster commands'))

verify()
verify(True)
