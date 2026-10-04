; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored frame-copy workload through the real CPU caches and PC98 fabric.
bits 16
cpu 386
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
mov al,07h
out 6ah,al
mov al,21h
out 6ah,al
mov byte [0e0102h],1
mov dx,7fe4h
mov eax,1
out dx,ax
; Distinct words exercise the texture/source cache instead of a constant fill.
mov edi,100000h
mov ecx,16000
mov eax,31415926h
fill:
stosd
add eax,01030711h
loop fill
mov dx,7fe4h
mov eax,2
out dx,ax
; Full 320x200-byte software framebuffer, copied with the stock x86 instruction.
mov esi,100000h
mov edi,0f00000h
mov ecx,16000
rep movsd
mov dx,7fe4h
mov eax,3
out dx,ax
; Read via the high alias after the final write. This also tests ordering.
mov esi,0fff00000h
mov ecx,16000
mov edx,31415926h
verify:
lodsd
cmp eax,edx
jne fail
add edx,01030711h
loop verify
mov dx,7ff0h
mov ax,600dh
out dx,ax
hang: jmp hang
fail:
mov dx,7ff0h
mov ax,0deadh
out dx,ax
jmp hang
align 8
gdt: dq 0
dw 0ffffh,0
db 0,09ah,0cfh,0
dw 0ffffh,0
db 0,092h,0cfh,0
gdtr: dw $-gdt-1
dd gdt
