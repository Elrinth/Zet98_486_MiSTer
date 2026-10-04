; SPDX-License-Identifier: GPL-3.0-or-later
; Native extended-RAM instruction fills and self-modifying-code coherence.
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
mov esi,payload
mov edi,1000000h
mov ecx,(payload_end-payload)/4
rep movsd
mov edi,1000000h
call edi
cmp eax,20202020h
jne fail
; The copied first ADD's immediate is at +3. It is already in the I-cache.
mov dword [1000003h],02020202h
call edi
cmp eax,21212121h
jne fail
; Its backing bytes must agree after instruction fetch and cache patching.
cmp dword [1000003h],02020202h
jne fail
mov ax,600dh
report:
mov dx,7ff0h
out dx,ax
hang:jmp hang
fail:
mov ax,0deadh
jmp report
align 16
payload:
xor eax,eax
times 32 add eax,01010101h
ret
align 4,db 90h
payload_end:
align 8
gdt:dq 0
dw 0ffffh,0
db 0,09ah,0cfh,0
dw 0ffffh,0
db 0,092h,0cfh,0
gdtr:dw $-gdt-1
dd gdt
