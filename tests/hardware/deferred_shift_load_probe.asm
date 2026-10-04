; SPDX-License-Identifier: GPL-3.0-or-later
; An older deferred shift and a younger cached load can write EAX together.
; The younger load wins; an independent following load permits that overlap.
; Vary instruction-line alignment and repeat warm code to cover the pipeline.
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
mov dword [7dfa8h],322ebb2dh
mov eax,[7dfa8h]
mov ebp,7e000h
mov word [ebp+30h],1234h
movzx esi,word [ebp+30h]
mov ecx,2
again:
%rep 64
mov eax,6d64c716h
mov [50000h],eax
mov [50004h],ebx
mov [50008h],ecx
mov [5000ch],edx
mov [50010h],esi
mov [50014h],edi
mov [50018h],ebp
mov [5001ch],esp
shl eax,1
mov eax,[ebp-58h]
movzx esi,word [ebp+30h]
add edi,8fb6h
cmp eax,322ebb2dh
jne fail
cmp esi,1234h
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
