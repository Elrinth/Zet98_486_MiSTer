; SPDX-License-Identifier: GPL-3.0-or-later
; An older VIPT memory ALU commits while a younger partial load captures
; its merge base. A following LEA must retain the older ALU's upper lanes.
; Check low/high bytes, words, and dependent memory ALUs at varied alignments.
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
mov dword [489dch],0ec3eeab1h
mov dword [ebp-112],404e711ch
mov dword [ebp-68],7b4de150h
mov ebx,[489dch]
mov ecx,2
again:
%rep 64
mov eax,[ebp-112]
sar eax,2
xor eax,[489dch]
mov al,[ebp-68]
lea edx,[eax+5]
cmp edx,0fc2d7655h
jne fail
nop
mov eax,[ebp-112]
sar eax,2
xor eax,[489dch]
mov ah,[ebp-68]
lea edx,[eax+5]
cmp edx,0fc2d50fbh
jne fail
nop
mov eax,[ebp-112]
sar eax,2
xor eax,[489dch]
mov ax,[ebp-68]
lea edx,[eax+5]
cmp edx,0fc2de155h
jne fail
nop
; A younger memory ALU also reads the old destination at its EX edge.
mov eax,10139c47h
xor eax,[489dch]
xor eax,[489dch]
cmp eax,10139c47h
jne fail
nop
%endrep
dec ecx
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
