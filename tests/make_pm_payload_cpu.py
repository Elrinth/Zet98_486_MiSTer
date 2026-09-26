"""Generate only self-authored test vectors; zlib is the independent oracle."""
from pathlib import Path
import sys,zlib
cases=[(0x110001,8191),(0x1ffffd,4097),(0x1000001,4097),(0x3df0003,8193)]
if '--limit-short' in sys.argv: cases=[(0x110001,16)]
out=['bits 16','cpu 386','org 100h','cli','cld','mov ax,cs','mov ds,ax','mov es,ax',
     'mov ss,ax','mov sp,0fef0h','xor al,al','out 0f2h,al',
     'mov di,1000h','xor ebx,ebx',
     'table_loop:','mov eax,ebx','mov cx,8','bit_loop:','shr eax,1','jnc bit_next',
     'xor eax,0edb88320h','bit_next:','loop bit_loop','stosd','inc ebx',
     'cmp ebx,256','jb table_loop','call pm_initialize']
stage=0
for base,length in cases:
    out+=['mov dword [pm_crc],0ffffffffh']
    for offset in range(0,length,4096):
        n=min(4096,length-offset)
        expected=zlib.crc32(bytes((a*37+(a>>8)+(a>>16))&255 for a in range(base,base+offset+n)))
        stage+=1
        out += [f'mov bp,{stage}',f'mov dword [pm_address],{base+offset}',f'mov dword [pm_length],{n}',
                'call pm_window','cmp byte [pm_fault],0','jne fail',
                f'cmp dword [pm_crc],0x{expected^0xffffffff:08x}','jne fail',
                'cmp sp,0fef0h','jne fail','smsw ax','test al,1','jnz fail']
out+=['mov bp,100','mov dword [pm_length],0','call pm_window','cmp byte [pm_fault],1','jne fail',
      # Preserve the newly measured limit-check failure as a separate control.
      # Default tests #NP restoration, without relying on that failing path.
      'mov bp,101','%ifdef PM_LIMIT_CONTROL',
      'mov word [pm_gdt+40],0','mov byte [pm_gdt+46],40h',
      '%else','mov byte [pm_gdt+45],12h','%endif',
      '%ifdef PM_LIMIT_COLD','add dword [pm_address],4096','%endif',
      'mov ax,pm_gdt+40','mov dx,7fe2h','out dx,ax',
      'mov dword [pm_length],1','call pm_window','cmp byte [pm_fault],1','jne fail',
      'smsw ax','test al,1','jnz fail','cmp sp,0fef0h','jne fail',
      'mov ax,600dh','jmp report','fail:',
      'mov eax,[pm_crc]','mov ebx,[pm_address]','mov ecx,[pm_length]',
      'movzx esi,byte [pm_fault]','mov dx,7fe0h','out dx,ax',
      'mov ax,0deadh','report:',
      'mov dx,7ff0h','out dx,ax','hlt','jmp $',
      '%include "tests/hardware/pm_crc_window.inc"',
      '%if ($-$$+100h)>1000h','%error Code/table overlap','%endif']
Path(sys.argv[1]).write_text('\n'.join(out)+'\n')
