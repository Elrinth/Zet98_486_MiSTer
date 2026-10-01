; SPDX-License-Identifier: GPL-3.0-or-later
; 486 instructions in real mode: INVD, WBINVD (HSB.EXE flushes the cache with
; them after changing CR0.CD) and BSWAP. An INT 06h (#UD) handler
; records which ones fault (bit per instruction, EBX) and skips them. CPUID
; must still fault (the core reports no ID flag, like a 486SX). Port 7FE4h
; prints the registers; 7FF0h gets 600Dh when only CPUID faulted.
bits 16
cpu 486
org 1000h
cli
xor ax,ax
mov ds,ax
mov ss,ax
mov sp,9000h
mov word [6*4],ud_handler
mov word [6*4+2],0
xor ebx,ebx
mov byte [skip],2
mov cl,0
mov eax,11111111h
mov edx,22222222h
invd                            ; 0F 08: a plain no-op here
cmp eax,11111111h
jne fail
cmp edx,22222222h
jne fail
cmp sp,9000h
jne fail
mov cl,1
wbinvd                          ; 0F 09
mov cl,2
mov eax,12345678h
bswap eax                       ; 0F C8
cmp eax,78563412h
jne fail
mov cl,5
db 0fh,0a2h                      ; cpuid: must fault (no ID flag)
mov dx,7fe4h
out dx,ax
cmp ebx,20h                     ; only CPUID faulted
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
ud_handler:                     ; record bit CL, return past the 2-byte opcode
push bp
mov bp,sp
bts ebx,ecx
add word [bp+2],2
pop bp
iret
skip db 0
