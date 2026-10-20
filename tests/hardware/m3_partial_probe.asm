; SPDX-License-Identifier: GPL-3.0-or-later
; A byte/word load into a register right after a register-memory ALU op on
; the same register ("xor ebx,[m]; mov bx,[m]; mov eax,ebx"). The partial
; load must merge with the ALU result, not with the register before it.
; Each case runs back-to-back, then again with NOP padding (reference).
; Port 7FE4h prints the registers on a mismatch; 7FF0h gets 600Dh.
bits 16
cpu 486
org 1000h
cli
xor ax,ax
mov ds,ax
mov ss,ax
mov sp,9000h
mov bp,600h
mov dword [bp+8],0b63a24beh
mov dword [bp+12],8e3b0bddh
mov dword [bp+16],11112222h
mov si,0
jmp start

; CASE prod, R, R32, dst, size, fill, seed. 16-bit addressing keeps address-size
; prefixes (an extra decode cycle) out of the back-to-back window.
%macro CASE 7
    mov %3,%7
    times %6 nop
    %1 %2,[bp+8]
    mov %4,%5 [bp+12]
    mov eax,%3
    lea edi,[%3+1]
    mov [bp+32],eax
    mov [bp+36],edi
    mov %3,%7
    times 6 nop
    %1 %2,[bp+8]
    times 6 nop
    mov %4,%5 [bp+12]
    times 6 nop
    inc word [bp+40]
    cmp [bp+32],%3
    jne fail
    lea edi,[%3+1]
    cmp [bp+36],edi
    jne fail
%endmacro

; Word producers have no prefix; dword producers (66h) cover the upper half.
%macro REGS 4
    CASE %1,bx,ebx,bl,byte,%2,%3
    CASE %1,bx,ebx,bh,byte,%2,%4
    CASE %1,cx,ecx,cl,byte,%2,%3
    CASE %1,dx,edx,dh,byte,%2,%4
    CASE %1,ebx,ebx,bx,word,%2,%3
    CASE %1,ecx,ecx,cx,word,%2,%4
    CASE %1,esi,esi,si,word,%2,%3
%endmacro

start:
mov word [bp+40],0
%assign f 0
%rep 4
    REGS add,f,0fff82391h,12345678h
    REGS xor,f,9abcdef0h,0fff82391h
    REGS sub,f,0c3c3a5a5h,7e7e1818h
    REGS and,f,0ffff0000h,5a5a5a5ah
%assign f f+1
%endrep
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
