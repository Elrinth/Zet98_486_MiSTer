; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored actual-CPU test. No game, BIOS or other private code.
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
; Keep unrelated low/extended RAM sentinels around the new aperture.
mov dword [100000h],13579bdfh
mov dword [1000000h],2468ace0h
mov dword [0a7ffch],10203040h
mov al,07h
out 6ah,al
mov al,21h
out 6ah,al
mov dx,9a0h
mov al,0ah
out dx,al
in al,dx
test al,1
jz fail
; Full 8-bit palette index, every component, real CPU IN/OUT and bus ACKs.
xor ecx,ecx
palette:
mov eax,ecx
out 0a8h,al
xor al,57h
out 0ach,al
mov eax,ecx
xor al,0b3h
out 0aah,al
mov eax,ecx
xor al,0c6h
out 0aeh,al
in al,0a8h
cmp al,cl
jne fail
in al,0ach
xor al,57h
cmp al,cl
jne fail
in al,0aah
xor al,0b3h
cmp al,cl
jne fail
in al,0aeh
xor al,0c6h
cmp al,cl
jne fail
inc ecx
cmp ecx,256
jb palette
mov byte [0e0102h],1
xor ebx,ebx
bank:
mov [0e0004h],bl
mov [0e0006h],bl
mov esi,ebx
shl esi,15
add esi,0f00000h
mov edi,ebx
shl edi,15
add edi,0fff00000h
mov eax,89abcdefh
xor eax,ebx
mov [0a8000h],eax
cmp [esi],eax
jne fail
cmp [edi],eax
jne fail
; Odd dword straddles three halfword requests and a DDR-word boundary.
mov dword [0b0007h],76543210h
cmp dword [esi+7],76543210h
jne fail
cmp dword [edi+7],76543210h
jne fail
mov byte [edi+1],55h
mov byte [0a8000h],66h
cmp word [0b0000h],5566h
jne fail
mov word [edi+7ffeh],0beefh
cmp word [0afffeh],0beefh
jne fail
inc ebx
cmp ebx,16
jb bank
cmp dword [0f80000h],0ffffffffh
jne fail
cmp dword [0fff80000h],0ffffffffh
jne fail
mov byte [0e0100h],1
cmp word [0a8000h],0ffffh
jne fail
cmp word [0b8000h],0ffffh
jne fail
cmp word [0fff7fffeh],0beefh
jne fail
mov al,20h
out 6ah,al
cmp word [0f7fffeh],0beefh
jne fail
cmp dword [100000h],13579bdfh
jne fail
cmp dword [1000000h],2468ace0h
jne fail
cmp dword [0a7ffch],10203040h
jne fail
mov ax,600dh
jmp report
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
gdtr:
dw 23
dd gdt
