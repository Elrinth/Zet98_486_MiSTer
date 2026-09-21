; SPDX-License-Identifier: GPL-3.0-or-later
; PC-98 1.23 MB floppy IPL. Loads four 1024-byte sectors into the resident
; test area, then starts ide_bootstrap.asm built with -DBIOS_BOOT=1.
; No DOS, original boot code, filesystem or HDD writes are embedded here.
bits 16
cpu 386
org 0
    jmp short start
    db 'Zet98 VHD bootstrap'
start:
    cli
    mov ax,0d800h
    mov ss,ax
    mov sp,07ffeh
    cld
    xor ax,ax
    mov ds,ax
    mov al,[0584h]
    and al,0fh
    or al,90h                 ; 2HD floppy, drive selected by the ROM
    mov [cs:drive],al
    mov byte [cs:attempts],3
    sti
.retry:
    mov ax,0d800h
    mov es,ax
    mov bp,0100h
    mov bx,4096
    mov cx,0300h              ; N=3 (1024 bytes), cylinder zero
    mov dx,0002h              ; head zero, first payload sector is two
    mov al,[cs:drive]
    mov ah,0d6h
    int 1bh
    jnc .loaded
    dec byte [cs:attempts]
    jnz .retry
    mov ax,0a000h
    mov es,ax
    xor di,di
    push cs
    pop ds
    mov si,error
.message:
    lodsb
    test al,al
    jz .stop
    xor ah,ah
    stosw
    mov word [es:di+2000h-2],0e1h
    jmp .message
.stop:
    cli
    hlt
    jmp .stop
.loaded:
    jmp 0d800h:0100h
drive: db 0
attempts: db 0
error: db 'Zet98: could not read resident VHD loader from floppy.',0
times 1024-($-$$) db 0
