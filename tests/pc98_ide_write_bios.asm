; SPDX-License-Identifier: GPL-3.0-or-later
bits 16
cpu 386
org 1000h
%define BIOS_HEADS 8
%define BIOS_SECTORS 17
%define BIOS_CYLINDERS 8162
%define BIOS_POLL_LIMIT 64
%define BIOS_ALLOW_WRITES 1
%define BIOS_WRITE_FIRST_LBA 17
%define BIOS_WRITE_LAST_LBA 100000
%ifdef BIOS_WRITE_SMOKE
    cli
    xor ax,ax
    mov ds,ax
    mov ss,ax
    mov sp,9000h
    mov word [1bh*4],bios_int1b
    mov word [1bh*4+2],0
    mov ax,2000h
    mov es,ax
    mov di,0fff0h
    mov cx,16
    mov al,27h
    cld
.first:
    stosb
    inc al
    loop .first
    ; Continue the physical buffer beyond the original segment boundary.
    mov dx,3000h
    mov es,dx
    xor di,di
    mov cx,497
.rest:
    stosb
    inc al
    loop .rest
    mov ax,2000h
    mov es,ax
    mov ebp,1122fff0h
    mov ebx,33440201h
    mov ecx,55660011h
    mov edx,77880000h
    mov eax,0aabb0500h
    std
    int 1bh
    jc failed
    cmp eax,0aabb0000h
    jne failed
    cmp ebp,1122fff0h
    jne failed
    cmp ebx,33440201h
    jne failed
    cmp ecx,55660011h
    jne failed
    cmp edx,77880000h
    jne failed
    pushf
    pop ax
    test ax,400h
    jz failed
    cld
    mov ax,4000h
    mov es,ax
    mov bp,100h
    mov bx,1024
    mov cx,17
    xor dx,dx
    mov ax,0600h
    int 1bh
    jc failed
    mov di,100h
    mov cx,513
    mov al,27h
.verify:
    cmp [es:di],al
    jne failed
    inc di
    inc al
    loop .verify
    cmp byte [es:di],0a5h   ; retained high byte of sector 18 word 0
    jne failed
    inc di
    mov cx,255
    mov dx,1
.tail:
    mov ax,0a55ah ^ 18
    xor ax,dx
    cmp [es:di],ax
    jne failed
    add di,2
    inc dx
    loop .tail
    mov ax,0500h
    mov bx,512
    mov cx,16               ; outside the explicit window
    xor dx,dx
    int 1bh
    jnc failed
    cmp ah,70h
    jne failed
    mov dx,7ff2h
    mov ax,3                ; ATA command error, no data phase
    out dx,ax
    mov ax,0500h
    mov cx,19
    xor dx,dx
    int 1bh
    jnc failed
    cmp ah,60h
    jne failed
    mov ax,600dh
    jmp result
failed:
    mov ax,0deadh
result:
    mov dx,7ff0h
    out dx,ax
    hlt
%else
db 'Z98W'
dw bios_int1b, chained
    int 1bh
    hlt
%endif
bios_previous_vector: dw chained,0
chained:
    mov ah,0aah
    iret
%include "software/pc98_ide_read_bios.inc"
