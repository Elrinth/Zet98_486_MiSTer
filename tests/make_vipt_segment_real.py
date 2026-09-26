"""Self-authored real-mode direct-load limit tests, no ROM or game payload."""
from pathlib import Path
import sys,json
out=Path(sys.argv[1]);out.mkdir(exist_ok=True)
cases=[]
for warm in (False,True):
    for width in (1,2,4):
        for mode in ('valid','cross','outside','addr16'):
            if width==1 and mode=='cross':continue
            if mode=='addr16' and width!=1:continue
            offset=0x10000-width if mode=='valid' else 0x10001-width if mode=='cross' else 0x10000
            if mode=='addr16':offset=0xbeefffff
            fault=mode in ('cross','outside')
            instruction={1:'mov bl,byte',2:'mov bx,word',4:'mov ebx,dword'}[width]
            value={1:0x12345676,2:0x12347654,4:0x76543210}[width]
            name=f'real-{"warm" if warm else "cold"}-{width}-{mode}'
            text=f'''bits 16
cpu 386
org 100h
cli
cld
mov ax,cs
mov ds,ax
mov ss,ax
mov fs,ax
mov sp,0f000h
xor ax,ax
mov es,ax
mov word [es:13*4],gp_handler
mov ax,cs
mov word [es:13*4+2],ax
mov ax,cs
mov es,ax
mov di,0fffch
mov dword [di],76543210h
mov word [faults],0
mov word [after_marker],0
'''
            if warm:text+='mov eax,[fs:di]\n'
            text+=f'''mov esi,0x{offset:08x}
mov ebx,12345678h
fault_instruction:
{instruction} [fs:{'si' if mode=='addr16' else 'esi'}]
mov word [after_marker],1
resume_check:
cmp word [faults],{int(fault)}
jne fail
cmp word [after_marker],{int(not fault)}
jne fail
cmp ebx,0x{0x12345678 if fault else value:08x}
jne fail
cmp sp,0f000h
jne fail
mov ax,600dh
jmp report
gp_handler:
; This real-mode control intentionally discards the exception frame. Precise
; saved-frame/IRETD checks are covered separately by the protected-mode suite.
cmp ebx,12345678h
jne fail
inc word [faults]
mov sp,0f000h
jmp resume_check
fail:
mov ax,0deadh
report:
mov dx,7ff0h
out dx,ax
hlt
jmp $
faults: dw 0
after_marker: dw 0
'''
            (out/(name+'.asm')).write_text(text)
            cases.append(dict(name=name,width=width,mode=mode,expected_fault=fault))
(out/'cases.json').write_text(json.dumps(cases,indent=2))
print('Generated',len(cases),'real-mode boundary cases')
