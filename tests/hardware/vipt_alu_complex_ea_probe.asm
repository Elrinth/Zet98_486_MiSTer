; SPDX-License-Identifier: GPL-3.0-or-later
; A complex EA may be prepared on the same edge as a VIPT ALU writes its
; index register. The partial sum must be refreshed after the commit edge.
; An independent load between the ALU and LEA exercises the overlap.
bits 16
cpu 486
org 1000h
cli
cld
xor ax,ax
mov ds,ax
mov ss,ax
mov sp,9000h
out 0f2h,al
lgdt [gdtr]
mov eax,cr0
or al,1
mov cr0,eax
jmp dword 08h:protected
bits 32
protected:
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,9000h
mov ebp,7e000h
mov dword [91274h],3a0af086h
mov dword [ebp+12],0a9eae8d1h
mov dword [ebp-108],5156e75bh
mov ebx,[ebp+12]
mov edi,2
again:
%rep 64
mov eax,5156e75ah
mov edx,[91274h]
add edx,[ebp+12]
mov esi,[ebp-108]
lea esi,[eax+edx*2+230]
cmp esi,19429aeeh
jne fail
nop
%endrep
dec edi
jnz again
mov ax,600dh
report:
mov dx,7ff0h
out dx,ax
hang:jmp hang
fail:
mov ax,0deadh
jmp report
align 8
gdt:dq 0
dw 0ffffh,0
db 0,09ah,0cfh,0
dw 0ffffh,0
db 0,092h,0cfh,0
gdtr:dw $-gdt-1
dd gdt
