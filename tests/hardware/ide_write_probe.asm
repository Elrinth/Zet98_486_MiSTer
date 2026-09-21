; SPDX-License-Identifier: GPL-3.0-or-later
; Disposable 1 MB image only; verify capacity and marker before enabling any
; write. The compiled BIOS additionally permits writes to sector 17 only.
bits 16
cpu 386
org 100h
%define BIOS_HEADS 4
%define BIOS_SECTORS 16
%define BIOS_CYLINDERS 32
%define BIOS_ALLOW_WRITES 1
%define BIOS_WRITE_FIRST_LBA 17
%define BIOS_WRITE_LAST_LBA 17
start:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,0fffeh
    mov ds,ax
    mov es,ax
    cld
    sti
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,0432h
    xor al,al
    out dx,al
    mov dx,074ch
    mov al,2
    out dx,al
    call bios_wait_idle
    jc pio_failed
    mov dx,064ch
    mov al,0e0h
    out dx,al
    mov dx,064eh
    mov al,0ech
    out dx,al
    call bios_wait_data
    jc pio_failed
    mov dx,0640h
    mov di,buffer
    mov cx,256
    rep insw
    call bios_end_pio
    cmp word [buffer+120],2048
    jne finish
    cmp word [buffer+122],0
    jne finish
    mov byte [stage],'1'
    mov ax,351bh
    int 21h
    mov [bios_previous_vector],bx
    mov [bios_previous_vector+2],es
    mov dx,bios_int1b
    mov ax,251bh
    int 21h
    push ds
    pop es
    mov bp,buffer
    mov bx,512
    xor cx,cx
    xor dx,dx
    mov ax,0600h
    int 1bh
    jc cleanup
    mov si,signature
    mov di,buffer
    mov cx,signature_end-signature
    repe cmpsb
    jne cleanup
    mov byte [stage],'2'
    ; Full-sector write through INT 1B, after both independent image guards.
    mov di,buffer
    xor dx,dx
    mov cx,256
.pattern:
    mov ax,dx
    xor ax,5a3ch
    stosw
    inc dx
    loop .pattern
    mov si,buffer
    mov di,expected
    mov cx,512
    rep movsb
    mov bp,buffer
    mov bx,512
    mov cx,17
    xor dx,dx
    mov ax,0500h
    int 1bh
    jc cleanup
    call read_compare
    jc cleanup
    mov byte [stage],'3'
    ; Odd partial write must retain all remaining bytes of the sector.
    mov di,expected
    mov cx,31
    mov al,80h
.partial:
    stosb
    inc al
    loop .partial
    mov bp,expected
    mov bx,31
    mov cx,17
    xor dx,dx
    mov ax,0580h             ; CHS: cylinder 0, head 1, sector 1
    xor cx,cx
    mov dx,0101h
    int 1bh
    jc cleanup
    call read_compare
    jc cleanup
    mov byte [stage],'4'
    mov bp,expected
    mov bx,512
    mov cx,16
    xor dx,dx
    mov ax,0500h
    int 1bh
    jnc cleanup
    cmp ah,70h
    jne cleanup
    mov cx,18
    mov ax,0500h
    int 1bh
    jnc cleanup
    cmp ah,70h
    jne cleanup
    mov byte [passed],1
cleanup:
    push ds
    lds dx,[bios_previous_vector]
    mov ax,251bh
    int 21h
    pop ds
    jmp finish
pio_failed:
    call bios_end_pio
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
read_compare:
    mov bp,readback
    mov bx,512
    mov cx,17
    xor dx,dx
    mov ax,0600h
    int 1bh
    jc .done
    mov si,expected
    mov di,readback
    mov cx,512
    repe cmpsb
    jne .bad
    clc
    ret
.bad:
    stc
.done:
    ret
critical_error:
    mov al,3
    iret
bios_previous_vector: dd 0
passed: db 0
message: dw 0
length: dw 0
log_name: db 'Z98HDWR.TXT',0
signature: db 'Z98 IDE DIAGNOSTIC ONLY',13,10
signature_end:
fail_text: db 13,10,'FAIL: bounded PC-98 write BIOS, stage '
stage: db '0',13,10,0
pass_text: db 13,10,'PASS: 1MB diagnostic image guards, BIOS sector 17',13,10
    db 'full/partial write and readback, CHS/LBA, protected neighbors.',13,10,0
%include "software/pc98_ide_read_bios.inc"
times 0 * (1 / (($ - $$) < 1f00h)) db 0
buffer equ 2000h
expected equ 2200h
readback equ 2400h
