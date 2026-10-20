; SPDX-License-Identifier: GPL-3.0-or-later
; CRCF.COM FILE: read FILE through DOS in 4 KB chunks and print its byte
; count and a rotate-add checksum (compare cores on the same disk image).
bits 16
cpu 486
org 100h
    mov si,81h
.skip: lodsb
    cmp al,' '
    je .skip
    dec si
    mov dx,si
.end: lodsb
    cmp al,13
    jne .end
    mov byte [si-1],0
    mov ax,3d00h
    int 21h
    jc .err
    mov bx,ax
    xor ebp,ebp                 ; checksum
    xor edi,edi                 ; length
.rd: mov ah,3fh
    mov cx,1000h
    mov dx,buf
    int 21h
    jc .err
    test ax,ax
    jz .done
    movzx ecx,ax
    add edi,ecx
    mov si,buf
.c: lodsb
    movzx eax,al
    add ebp,eax
    rol ebp,3
    loop .c
    jmp .rd
.done:
    mov ah,3eh
    int 21h
    mov eax,edi
    call hex32
    mov dl,' '
    mov ah,2
    int 21h
    mov eax,ebp
    call hex32
    mov dx,crlf
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
.err:
    mov dx,errmsg
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
hex32:
    mov cx,8
.h: rol eax,4
    push eax
    and al,0fh
    add al,'0'
    cmp al,'9'
    jbe .p
    add al,7
.p: mov dl,al
    mov ah,2
    int 21h
    pop eax
    loop .h
    ret
errmsg db 'CRCF: cannot read',13,10,'$'
crlf   db 13,10,'$'
buf:
