#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Optional fast complement to run-ide-bios.sh; requires unicorn==2.1.4.
import sys,struct
from pathlib import Path
from collections import deque
from unicorn import *
from unicorn.x86_const import *
u=Uc(UC_ARCH_X86,UC_MODE_16);u.mem_map(0,0x200000)
u.mem_write(0x1000,Path(sys.argv[1]).read_bytes())
ports={};state={'fault':0,'status':0x50,'delay':0,'word':0,'lba':0,'reads':0,'passed':False}
history=deque(maxlen=20)
def code(uc,address,size,data):history.append(address)
def outp(uc,port,size,value,data):
 ports[port]=value
 if port==0x7ff2:
  state['fault']=value;state['status']=0 if value==1 else 0x80 if value==2 else 0x50
 if port==0x64e:
  assert value==0x20,(port,value)
  assert ports[0x644]==1
  state['lba']=ports[0x646]|ports[0x648]<<8|ports[0x64a]<<16|(ports[0x64c]&15)<<24
  state['word']=0;state['delay']=3;state['status']=0x80;state['reads']+=1
 if port==0x7ff0:
  print('Result',hex(value),'reads',state['reads'],'history',[hex(n) for n in history])
  state['passed']=value==0x600d and state['reads']==135 and ports.get(0x74c)==0
  uc.emu_stop()
def inp(uc,port,size,data):
 if port in (0x74c,0x64e):
  if state['delay']:
   state['delay']-=1
   if not state['delay']:state['status']=0x51 if state['fault']==3 else 0x58
  return state['status']
 if port==0x640:
  assert size==2 and state['status']==0x58
  value=(0xa55a^state['lba']^state['word'])&65535
  state['word']+=1
  if state['word']==256:state['status']=0x50
  return value
 return ports.get(port,(1<<(8*size))-1)
def interrupt(uc,vector,data):
 flags=uc.reg_read(UC_X86_REG_EFLAGS);cs=uc.reg_read(UC_X86_REG_CS);ip=uc.reg_read(UC_X86_REG_IP)
 sp=uc.reg_read(UC_X86_REG_SP);ss=uc.reg_read(UC_X86_REG_SS)
 for word in (flags,cs,ip):
  sp=(sp-2)&65535;uc.mem_write(ss*16+sp,struct.pack('<H',word&65535))
 uc.reg_write(UC_X86_REG_SP,sp);uc.reg_write(UC_X86_REG_EFLAGS,flags&~0x300)
 ip,cs=struct.unpack('<HH',uc.mem_read(vector*4,4));uc.reg_write(UC_X86_REG_CS,cs);uc.reg_write(UC_X86_REG_IP,ip)
u.hook_add(UC_HOOK_CODE,code);u.hook_add(UC_HOOK_INTR,interrupt)
u.hook_add(UC_HOOK_INSN,inp,None,1,0,UC_X86_INS_IN)
u.hook_add(UC_HOOK_INSN,outp,None,1,0,UC_X86_INS_OUT)
u.emu_start(0x1000,0x100000,count=5000000)
assert state['passed'],state
print('PASS independent x86 BIOS test')
