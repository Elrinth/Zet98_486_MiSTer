; SPDX-License-Identifier: GPL-3.0-or-later
; MEMSIZE.COM: print the BIOS memory-size bytes 0000:0401 (extended memory
; in 128 KB units below 16 MB), 0000:0594/0595 (MB above 16 MB) and 0:0501.
bits 16
org 100h
    xor ax,ax
    mov es,ax
    mov al,[es:0401h]
    call hex8
    mov al,[es:0594h]
    call hex8
    mov al,[es:0595h]
    call hex8
    mov al,[es:0501h]
    call hex8
    mov dx,crlf
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
hex8:
    push ax
    shr al,4
    call nib
    pop ax
    call nib
    mov dl,' '
    mov ah,2
    int 21h
    ret
nib:
    and al,0fh
    add al,'0'
    cmp al,'9'
    jbe .p
    add al,7
.p: mov dl,al
    mov ah,2
    int 21h
    ret
crlf db 13,10,'$'
