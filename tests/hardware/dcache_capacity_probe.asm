; SPDX-License-Identifier: GPL-3.0-or-later
; General 12 KB data-working-set benchmark with verified sums and byte writes.
bits 16
cpu 486
org 1000h
%define DATA_BASE 01000000h
%define WORDS 3072
%define EXPECTED (WORDS*(WORDS-1)/2)
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
mov edi,DATA_BASE
mov ecx,WORDS
xor eax,eax
fill:
stosd
inc eax
loop fill
call sum
cmp eax,EXPECTED
jne fail
mov dx,7fe4h
mov ax,1
out dx,ax
mov ebp,16
repeat_data:
call sum
cmp eax,EXPECTED
jne fail
dec ebp
jnz repeat_data
mov dx,7fe4h
mov ax,2
out dx,ax
; A byte write in the upper cache index range must patch only its own byte.
mov byte [DATA_BASE+0ff1h],80h
cmp dword [DATA_BASE+0ff0h],000080fch
jne fail
call sum
cmp eax,EXPECTED+07d00h
jne fail
mov ax,600dh
report:
mov dx,7ff0h
out dx,ax
hang:jmp hang
fail:
mov ax,0deadh
jmp report
sum:
mov esi,DATA_BASE
mov ecx,WORDS
xor ebx,ebx
read:
lodsd
add ebx,eax
loop read
mov eax,ebx
ret
align 8
gdt:dq 0
dw 0ffffh,0
db 0,09ah,0cfh,0
dw 0ffffh,0
db 0,092h,0cfh,0
gdtr:dw $-gdt-1
dd gdt
