; SPDX-License-Identifier: GPL-3.0-or-later
; 486 BSWAP r32 (0F C8+r) for all eight registers, flags unchanged.
; Port 7FE4h prints the registers on a mismatch; 7FF0h gets 600Dh.
bits 16
cpu 486
org 1000h
cli
xor ax,ax
mov ds,ax
mov ss,ax
mov sp,9000h
mov ebp,12345678h
mov eax,0a1b2c3d4h
mov ecx,0deadbeefh
mov edx,01020304h
mov ebx,0f0e0d0c0h
mov esi,089abcdefh
mov edi,0aabbccddh
push ebp
mov ebp,0cafebabeh
mov word [500h],sp
mov esp,0b5b6b7b8h
bswap esp
mov [504h],esp
mov sp,[500h]
mov dword [508h],esp
stc
bswap eax
bswap ecx
bswap edx
bswap ebx
bswap esi
bswap edi
bswap ebp
jnc fail
cmp eax,0d4c3b2a1h
jne fail
cmp ecx,0efbeaddeh
jne fail
cmp edx,04030201h
jne fail
cmp ebx,0c0d0e0f0h
jne fail
cmp esi,0efcdab89h
jne fail
cmp edi,0ddccbbaah
jne fail
cmp ebp,0bebafecah
jne fail
cmp dword [504h],0b8b7b6b5h
jne fail
bswap eax
cmp eax,0a1b2c3d4h
jne fail
mov ax,600dh
jmp report
fail:
mov dx,7fe4h
out dx,ax
mov ax,0deadh
report:
mov dx,7ff0h
out dx,ax
hlt
jmp $
