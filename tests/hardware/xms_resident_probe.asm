; SPDX-License-Identifier: GPL-3.0-or-later
; Calls a separately supplied, initialized XMS resident-driver snapshot.
; The fixture already owns an unlocked 19 KB block with handle 0664h.
bits 16
cpu 386
org 1000h
    cli
    cld
    xor ax,ax
    mov ds,ax
    mov ax,0b4eh
    mov ss,ax
    mov sp,0fffeh
    out 0f2h,al
    mov dword [20h],12345678h ; distinguish A20 aliases
%ifdef COPY_CONTROL
    mov dx,35
    mov ah,9
    call 058dh:0624h
    cmp ax,1
    jne fail
    mov [move_desc+10],dx
    mov si,move_desc
    mov ah,0bh
%else
    mov dx,0664h
    mov bx,35
    mov ah,0fh
%endif
    call 058dh:0624h
    cmp ax,1
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
move_desc:
    dd 19*1024
    dw 0664h
    dd 0
    dw 0
    dd 0
