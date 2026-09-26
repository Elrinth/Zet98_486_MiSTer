; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored LSS ESP tests: GDT/LDT, low/extended RAM, all dword alignments.
; The restore operand uses old SS:ESP while ESP and SS are being replaced.
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
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,90000h
mov ax,20h
lldt ax
xor edi,edi
selector_loop:
xor esi,esi
alignment_loop:
mov eax,88000h
add eax,esi
mov [pair+8],eax
movzx eax,word [selectors+edi*2]
mov [pair+12],ax
mov edx,pair
lss esp,[edx+8]
cmp esp,[pair+8]
jne fail
xor eax,eax
mov ax,ss
cmp ax,[pair+12]
jne fail
mov dword [ss:esp],90000h
mov word [ss:esp+4],10h
push dword 13579bdfh
call callback
pop ebx
cmp ebx,13579bdfh
jne fail
lss esp,[esp]
cmp esp,90000h
jne fail
mov ax,ss
cmp ax,10h
jne fail
inc esi
cmp esi,4
jb alignment_loop
inc edi
cmp edi,4
jb selector_loop
cmp dword [visits],16
jne fail
mov ax,600dh
jmp report
callback:
pushad
mov eax,[ss:esp+36]
cmp eax,13579bdfh
jne fail
inc dword [visits]
popad
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
dw ldt_end-ldt-1
dw ldt
db 0,82h,0,0
gdtr: dw 39
dd gdt
ldt:
dq 0
dq 00cf92000000ffffh
dq 00cf92200000ffffh
ldt_end:
selectors: dw 10h,18h,0ch,14h
pair: times 16 db 0
visits: dd 0
