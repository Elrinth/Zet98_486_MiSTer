; SPDX-License-Identifier: GPL-3.0-or-later
; Self-contained protected-mode stack availability and allocation comparison.
; Tests both low RAM and extended RAM, without game or firmware assets.
bits 16
cpu 386
org 1000h
cli
cld
xor ax,ax
mov ds,ax
mov ss,ax
mov sp,9000h
lgdt [gdtr]
mov eax,cr0
or al,1
mov cr0,eax
jmp dword 08h:protected
bits 32
protected:
xor ebp,ebp
mode:
lea eax,[ebp*8+10h]
mov ds,ax
mov es,ax
mov ss,ax
mov esp,8b5a4h
mov esi,cases
next_case:
movzx eax,word [cs:esi]
mov [50008h],ax
mov ebx,esp
sub ebx,4
sub ebx,[cs:esi+6]
mov [49d2ch],ebx
movsx eax,word [50008h]
add eax,3
and al,0fch
mov edx,eax
call available
cmp eax,[cs:esi+6]
jne fail
cmp edx,[cs:esi+2]
jne fail
cmp edx,eax
jae insufficient
xor ecx,ecx
jmp compare
insufficient:
mov ecx,1
compare:
cmp ecx,[cs:esi+10]
jne fail
add esi,14
cmp esi,cases_end
jb next_case
inc ebp
cmp ebp,2
jb mode
mov ax,600dh
jmp report
available:
mov eax,esp
sub eax,[49d2ch]
ret
fail:
mov ax,0deadh
report:
mov dx,7ff0h
out dx,ax
hlt
jmp $
align 8
gdt:
dq 0
dq 00cf9a000000ffffh
dq 00cf92000000ffffh
dq 00cf92200000ffffh
gdtr:
dw 31
dd gdt
cases:
dw 24
dd 24,63629,0
dw 24
dd 24,1,1
dw 24
dd 24,16,1
dw 24
dd 24,24,1
dw 24
dd 24,25,0
dw 32768
dd 4294934528,63629,1
dw 32768
dd 4294934528,1,1
dw 32768
dd 4294934528,16,1
dw 32768
dd 4294934528,24,1
dw 32768
dd 4294934528,25,1
dw 65535
dd 0,63629,0
dw 65535
dd 0,1,0
dw 65535
dd 0,16,0
dw 65535
dd 0,24,0
dw 65535
dd 0,25,0
dw 0
dd 0,63629,0
dw 0
dd 0,1,0
dw 0
dd 0,16,0
dw 0
dd 0,24,0
dw 0
dd 0,25,0
dw 8
dd 8,63629,0
dw 8
dd 8,1,1
dw 8
dd 8,16,0
dw 8
dd 8,24,0
dw 8
dd 8,25,0
dw 255
dd 256,63629,0
dw 255
dd 256,1,1
dw 255
dd 256,16,1
dw 255
dd 256,24,1
dw 255
dd 256,25,1
dw 256
dd 256,63629,0
dw 256
dd 256,1,1
dw 256
dd 256,16,1
dw 256
dd 256,24,1
dw 256
dd 256,25,1
dw 32767
dd 32768,63629,0
dw 32767
dd 32768,1,1
dw 32767
dd 32768,16,1
dw 32767
dd 32768,24,1
dw 32767
dd 32768,25,1
cases_end:
