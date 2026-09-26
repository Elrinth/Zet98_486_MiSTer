; SPDX-License-Identifier: GPL-3.0-or-later
; Actual CPU/BIOS copy test: every alignment and all DWORD tail classes.
bits 16
cpu 386
org 1000h
%define BIOS_HEADS 8
%define BIOS_SECTORS 17
%define BIOS_CYLINDERS 8162
%define BIOS_POLL_LIMIT 256
start:
    cli
    xor ax,ax
%ifdef BIOS_HIGH_STACK
    mov ax,0d800h
%endif
    mov ss,ax
    mov sp,7000h
    xor ax,ax
    mov ds,ax
    mov es,ax
    cld
    mov word [1bh*4],bios_int1b
    mov word [1bh*4+2],0
    mov word [alignment],0
.alignment:
    mov word [case_index],0
.case:
    mov ax,2000h
    mov es,ax
    mov bp,[alignment]
    add bp,100h
    mov bx,[case_index]
    mov cx,[lengths+bx]
    mov [length],cx
    add cx,2
    mov di,bp
    dec di
    mov al,0cch
    rep stosb
    mov bx,[length]
    mov cx,101h
    xor dx,dx
    mov ax,0600h
    std
    int 1bh
    jc failed
    pushf
    pop ax
    test ax,400h
    jz failed
    cld
    mov di,bp
    cmp byte [es:di-1],0cch
    jne failed
    add di,[length]
    cmp byte [es:di],0cch
    jne failed
    xor si,si
    mov di,bp
.byte:
    mov dx,si
    shr dx,9
    add dx,101h
    mov ax,0a55ah
    xor ax,dx
    mov dx,si
    shr dx,1
    and dx,255
    xor ax,dx
    test si,1
    jz .low
    shr ax,8
.low:
    cmp al,[es:di]
    jne failed
    inc di
    inc si
    cmp si,[length]
    jb .byte
    add word [case_index],2
    cmp word [case_index],lengths_end-lengths
    jb .case
    inc word [alignment]
    cmp word [alignment],16
    jb .alignment
    mov dx,7ff0h
    mov ax,600dh
    out dx,ax
    hlt
failed:
    mov dx,7ff0h
    mov ax,0deadh
    out dx,ax
    hlt
alignment: dw 0
case_index: dw 0
length: dw 0
lengths: dw 1,2,3,4,5,7,511,512,513,514,515,1023,1024
lengths_end:
previous_handler: iret
bios_previous_vector: dw previous_handler,0
%include "software/pc98_ide_read_bios.inc"
