"""Bounded BIOS cost probe: protocol negatives plus actual production-ROM path."""
from pathlib import Path
import sys,struct,json,zlib
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'build/verification-python'))
from unicorn import *
from unicorn.x86_const import *
from ide_bootrom_unicorn import Machine

class ProbeMachine(Machine):
 def __init__(self,rom,case,actual):
  self.case,self.actual,self.probing=case,actual,False
  self.rtc=0;self.bios_calls=[];self.written=b'';self.exit=None
  super().__init__(rom)
 def interrupt(self,u,vector,_):
  if not self.probing:return super().interrupt(u,vector,_)
  ax,bx,cx,dx=[u.reg_read(r) for r in (UC_X86_REG_AX,UC_X86_REG_BX,UC_X86_REG_CX,UC_X86_REG_DX)]
  ptr=u.reg_read(UC_X86_REG_DS)*16+dx
  def error():u.reg_write(UC_X86_REG_EFLAGS,u.reg_read(UC_X86_REG_EFLAGS)|1)
  if vector==0x1b:
   assert ax in (0x600,0x100) and bx==32768 and dx<256
   lba=(dx<<16)|cx;self.bios_calls.append((ax>>8,lba))
   if self.case=='bios_error':error();return
   if self.case=='status_error':u.reg_write(UC_X86_REG_AX,0x6000);return
   if self.actual:return super().interrupt(u,vector,_)
   u.reg_write(UC_X86_REG_EFLAGS,u.reg_read(UC_X86_REG_EFLAGS)&~1)
   if ax==0x600 or self.case=='verify_writes':
    payload=b''.join(self.sector(lba+i) for i in range(64))
    if self.case=='wrong_read':payload=bytes([payload[0]^1])+payload[1:]
    u.mem_write(u.reg_read(UC_X86_REG_ES)*16+u.reg_read(UC_X86_REG_BP),payload)
   u.reg_write(UC_X86_REG_AX,0);return
  if vector==0x1c:
   assert ax>>8==0;self.rtc+=1
   sec=(self.rtc//32 if self.case!='frozen_clock' else 0)
   if self.case=='timeout' and self.bios_calls:sec+=60
   if self.case=='midnight':sec+=86398
   sec%=86400
   def bcd(v):return v//10*16+v%10
   t=bytes([0,0,0,bcd(sec//3600),bcd(sec//60%60),bcd(sec%60)])
   if self.case=='bad_clock':t=t[:5]+b'\x6a'
   u.mem_write(u.reg_read(UC_X86_REG_ES)*16+bx,t);return
  assert vector==0x21
  u.reg_write(UC_X86_REG_EFLAGS,u.reg_read(UC_X86_REG_EFLAGS)&~1)
  ah=ax>>8
  if ah in (9,0x25,0x0d):return
  if ah==0x5b:
   assert bytes(u.mem_read(ptr,32)).split(b'\0')[0]==b'A:\\BIOSCOST.BIN'
   if self.case=='existing':error()
   else:u.reg_write(UC_X86_REG_AX,8)
  elif ah==0x40:
   assert bx==8 and cx==128
   n=127 if self.case=='short_write' else cx
   self.written=bytes(u.mem_read(ptr,n));u.reg_write(UC_X86_REG_AX,n)
  elif ah==0x3e:pass
  elif ah==0x4c:self.exit=ax&255;u.emu_stop()
  else:raise AssertionError(hex(ax))
 def output(self,u,port,size,value,_):
  assert not(port==0x64e and value==0x30),'Probe must never write disk'
  return super().output(u,port,size,value,_)

def run(rom,binary,case,actual=False):
 m=ProbeMachine(rom,case,actual);assert m.initialize()==1
 m.commands=[];m.probing=True;u=m.u
 u.mem_write(0x10100,binary);u.mem_write(0x10002,b'\0\x90')
 for r in (UC_X86_REG_CS,UC_X86_REG_DS,UC_X86_REG_ES,UC_X86_REG_SS):u.reg_write(r,0x1000)
 u.reg_write(UC_X86_REG_SP,0xfffe);u.reg_write(UC_X86_REG_EFLAGS,0x602 if case=='df_set' else 0x202)
 u.emu_start(0x10100,0,count=20000000)
 good=case in ('normal','df_set','midnight','wrong_read')
 assert m.exit==(0 if good else 1),(case,actual,m.exit)
 if good:
  r=m.written;assert r[:8]==b'Z98BIO1\0' and len(r)==128
  lba,total,chunk,phases=struct.unpack_from('<4I',r,8)
  assert (lba,chunk,phases)==(136,32768,4) and r[24:32]==bytes(8) and r[96:]==bytes(32)
  n=total//chunk
  assert m.bios_calls==[(c,136+64*i) for c in (6,1,1,6) for i in range(n)]
  tail=b''.join(m.sector(136+(n-1)*64+i) for i in range(64))
  for i,c in enumerate((6,1,1,6)):
   command,seconds,crc,passed=struct.unpack_from('<4I',r,32+i*16)
   expected=zlib.crc32(tail if c==6 else b'\x5a\xa5'*16384)
   assert command==c and seconds<60 and passed==1
   if case=='wrong_read' and c==6:assert crc!=expected
   else:assert crc==expected,(i,hex(crc),hex(expected))
  if actual:assert m.commands==[(0x20,l) for c in (6,1,1,6) for l in range(136,136+total//512)]
 return dict(case=case,actual_production_bios=actual,passed=True,bios_calls=len(m.bios_calls),ata_reads=len(m.commands))

if __name__=='__main__':
 rom=Path(sys.argv[1]).read_bytes();full=Path(sys.argv[2]).read_bytes();small=Path(sys.argv[3]).read_bytes()
 cases=['normal','df_set','midnight','wrong_read','bios_error','status_error','verify_writes','existing','short_write','bad_clock','frozen_clock','timeout']
 results=[run(rom,full,c) for c in cases]
 results.append(run(rom,small,'normal',True))
 print(json.dumps(dict(passed=True,cases=results),indent=2))
