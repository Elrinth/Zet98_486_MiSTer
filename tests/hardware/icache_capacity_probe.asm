; SPDX-License-Identifier: GPL-3.0-or-later
; General instruction-working-set benchmark, with SMC in the upper cache sets.
; The 12 KB routine exceeds an 8 KB cache but fits a 16 KB cache. Nothing in
; this test or the cache configuration depends on a game or executable name.
bits 16
cpu 486
org 1000h
%define CODE_BASE 01000000h
%define ADD_COUNT 2400
%define ADD_VALUE 01010101h
%define EXPECTED ((ADD_COUNT * ADD_VALUE) & 0ffffffffh)
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
mov edi,CODE_BASE
mov ecx,(payload_end-payload)/4
rep movsd
mov edi,CODE_BASE
call edi
cmp eax,EXPECTED
jne fail
mov dx,7fe4h
mov ax,1
out dx,ax
mov ecx,32
repeat_code:
call edi
cmp eax,EXPECTED
jne fail
loop repeat_code
mov dx,7fe4h
mov ax,2
out dx,ax
; Offset 11003 has index bit 11 set: exercise the newly added half of sets.
mov dword [CODE_BASE+3+5*2200],2*ADD_VALUE
call edi
cmp eax,(EXPECTED+ADD_VALUE) & 0ffffffffh
jne fail
; Patch another cached line, preserving the earlier change.
mov dword [CODE_BASE+3],2*ADD_VALUE
call edi
cmp eax,(EXPECTED+2*ADD_VALUE) & 0ffffffffh
jne fail
cmp dword [CODE_BASE+3+5*2200],2*ADD_VALUE
jne fail
mov ax,600dh
report:
mov dx,7ff0h
out dx,ax
hang: jmp hang
fail:
mov ax,0deadh
jmp report
align 16
payload:
xor eax,eax
times ADD_COUNT add eax,ADD_VALUE
ret
align 4,db 90h
payload_end:
align 8
gdt: dq 0
dw 0ffffh,0
db 0,09ah,0cfh,0
dw 0ffffh,0
db 0,092h,0cfh,0
gdtr: dw $-gdt-1
dd gdt
