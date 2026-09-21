; SPDX-License-Identifier: GPL-3.0-or-later
; Read-only check of the owner's prepared 542 MiB DOS game image. The listed
; checksums identify test regions; they are not a general disk-integrity test.
bits 16
cpu 386
org 100h
%define BIOS_HEADS 8
%define BIOS_SECTORS 17
%define BIOS_CYLINDERS 8162
start:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,0fffeh
    mov ds,ax
    mov es,ax
    cld
    sti
    mov bx,1000h
    mov ah,4ah
    int 21h
    jc finish
    mov bx,1000h
    mov ah,48h
    int 21h
    jc finish
    mov [buffer_segment],ax
    mov ax,351bh
    int 21h
    mov [bios_previous_vector],bx
    mov [bios_previous_vector+2],es
    mov dx,bios_int1b
    mov ax,251bh
    int 21h
    mov byte [installed],1
    mov ax,8480h
    int 1bh
    jc cleanup
    cmp bx,512
    jne cleanup
    cmp cx,BIOS_CYLINDERS
    jne cleanup
    cmp dx,0811h
    jne cleanup
    mov byte [stage],'1'
    mov ax,[buffer_segment]
    mov es,ax
    xor bp,bp
    mov ax,0680h
    mov bx,1024
    xor cx,cx
    xor dx,dx
    int 1bh
    jc cleanup
    mov cx,512
    call checksum
    cmp ax,0f270h
    jne cleanup
    mov byte [stage],'2'
    mov ax,0600h
    mov bx,512
    mov cx,136
    xor dx,dx
    int 1bh
    jc cleanup
    mov cx,256
    call checksum
    cmp ax,09cbeh
    jne cleanup
    mov byte [stage],'3'
    mov ax,0680h
    mov bx,1024
    xor cx,cx
    mov dx,0710h           ; last sector before cylinder 1 / partition boot
    int 1bh
    jc cleanup
    mov cx,512
    call checksum
    cmp ax,09cbeh
    jne cleanup
    mov byte [stage],'4'
    mov ax,0600h
    xor bx,bx              ; 64K byte transfer
    xor cx,cx
    mov dx,1               ; linear LBA 65536
    int 1bh
    jc cleanup
    mov cx,32768
    call checksum
    cmp ax,022d0h
    jne cleanup
    mov byte [passed],1
cleanup:
    push ds
    lds dx,[bios_previous_vector]
    mov ax,251bh
    int 21h
    pop ds
    mov byte [installed],0
finish:
    mov si,fail_text
    cmp byte [passed],1
    jne .message
    mov si,pass_text
.message:
    mov [message],si
    xor cx,cx
.print:
    lodsb
    test al,al
    jz .save
    push cx
    push si
    mov dl,al
    mov ah,2
    int 21h
    pop si
    pop cx
    inc cx
    jmp .print
.save:
    mov [length],cx
    mov dx,log_name
    xor cx,cx
    mov ah,3ch
    int 21h
    jc halt
    mov bx,ax
    mov dx,[message]
    mov cx,[length]
    mov ah,40h
    int 21h
    mov ah,3eh
    int 21h
    mov ah,0dh
    int 21h
halt:
    sti
    hlt
    jmp halt
checksum:
    xor ax,ax
    xor di,di
.word:
    rol ax,1
    xor ax,[es:di]
    add di,2
    loop .word
    ret
bios_previous_vector: dd 0
buffer_segment: dw 0
installed: db 0
passed: db 0
message: dw 0
length: dw 0
log_name: db 'Z98HDRO.TXT',0
fail_text: db 13,10,'FAIL: read-only PC-98 disk BIOS test, stage '
stage: db '0',13,10,0
pass_text: db 13,10,'PASS: PC-98 disk BIOS geometry, IPL, partition,',13,10
    db 'CHS cylinder crossing and 64K linear read.',13,10
    db 'Game VHD was only read. HDD boot is not tested.',13,10,0
%include "software/pc98_ide_read_bios.inc"
