; SPDX-License-Identifier: GPL-3.0-or-later
; Repeatedly patch cached 32-bit routines at every byte alignment, including
; immediates spanning DWORD and cache-line boundaries. No OS/game dependency.
bits 16
cpu 486
org 1000h
%define CODE_BASE 01000000h
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
xor ebx,ebx
install:
call address
mov byte [edi],0b8h
mov dword [edi+1],0
mov byte [edi+5],0c3h
inc ebx
cmp ebx,64
jne install
xor ebx,ebx
warm:
call address
call edi
test eax,eax
jnz fail
inc ebx
cmp ebx,64
jne warm
mov esi,12345678h
mov ebp,32
round:
; Direct calls can launch prefetch earlier than the indirect warmup calls.
; Vary their distance from the store while keeping every expected value.
%assign SLOT 0
%rep 64
%assign ENTRY (CODE_BASE+SLOT*128+(SLOT & 15))
mov ebx,SLOT
mov [ENTRY+1],esi
times (SLOT & 7) nop
call ENTRY
cmp eax,esi
jne fail
xor byte [ENTRY+2],80h
xor esi,8000h
call ENTRY
cmp eax,esi
jne fail
cmp [ENTRY+1],esi
jne fail
add esi,01020304h
%assign SLOT SLOT+1
%endrep
dec ebp
jnz round
mov ax,600dh
report:
mov dx,7ff0h
out dx,ax
hang:jmp hang
fail:
mov dx,7fe4h
out dx,ax
mov ax,0deadh
jmp report
address:
mov edi,ebx
shl edi,7
mov eax,ebx
and eax,15
lea edi,[edi+eax+CODE_BASE]
ret
align 8
gdt:dq 0
dw 0ffffh,0
db 0,09ah,0cfh,0
dw 0ffffh,0
db 0,092h,0cfh,0
gdtr:dw $-gdt-1
dd gdt
