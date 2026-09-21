; SPDX-License-Identifier: GPL-3.0-or-later
; Silent diagnostic: consume UART ACK under CLI, then observe pending IRQ6.
; This reports behavior rather than assuming whether the PIC should retain it.
bits 16
cpu 8086
org 100h
start:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,0fffeh
    mov ds,ax
    mov es,ax
    cld
    sti
    mov ax,350eh
    int 21h
    mov [old_vector],bx
    mov [old_vector+2],es
    mov dx,handler
    mov ax,250eh
    int 21h
    cli
    in al,2
    mov [old_mask],al
    and al,0bfh
    out 2,al
    mov dx,0e0d2h
    mov cx,0ffffh
.ready:
    in al,dx
    test al,40h
    jz .command
    loop .ready
    jmp short .observe
.command:
    mov al,3fh
    out dx,al
    mov cx,0ffffh
.receive:
    in al,dx
    test al,80h
    jz .read_ack
    loop .receive
    jmp short .observe
.read_ack:
    mov dx,0e0d0h
    in al,dx
    mov [ack_byte],al
.observe:
    mov al,0ah
    out 0,al
    in al,0
    mov [pending],al
    sti
    mov ah,2ch
    int 21h
    mov [second],dh
.wait:
    mov ah,2ch
    int 21h
    cmp dh,[second]
    je .wait
    cli
    mov al,[old_mask]
    out 2,al
    mov al,20h
    out 0,al
    sti
    push ds
    lds dx,[old_vector]
    mov ax,250eh
    int 21h
    pop ds
    mov al,[ack_byte]
    mov di,ack_text
    call hexbyte
    mov al,[pending]
    mov di,pending_text
    call hexbyte
    mov al,[irq_count]
    mov di,irq_text
    call hexbyte
    mov al,[empty_count]
    mov di,empty_text
    call hexbyte
    mov dx,message
    mov ah,9
    int 21h
    mov dx,filename
    xor cx,cx
    mov ah,3ch
    int 21h
    jc .halt
    mov bx,ax
    mov dx,message
    mov cx,message_end-message
    mov ah,40h
    int 21h
    mov ah,3eh
    int 21h
    mov ah,0dh
    int 21h
.halt:
    cli
    hlt
    jmp short .halt
hexbyte:
    mov ah,al
    mov cl,4
    shr al,cl
    call nibble
    mov al,ah
    and al,0fh
nibble:
    add al,'0'
    cmp al,'9'
    jbe .store
    add al,7
.store:
    mov [di],al
    inc di
    ret
handler:
    push ax
    push dx
    push ds
    push cs
    pop ds
    inc byte [irq_count]
    mov dx,0e0d2h
    in al,dx
    test al,80h
    jz .drain
    inc byte [empty_count]
    jmp short .eoi
.drain:
    mov dx,0e0d0h
    in al,dx
.eoi:
    mov al,20h
    out 0,al
    pop ds
    pop dx
    pop ax
    iret
old_vector dw 0,0
old_mask db 0
ack_byte db 0
pending db 0
irq_count db 0
empty_count db 0
second db 0
filename db 'Z98POL.TXT',0
message db 'MPU polled UART ACK='
ack_text db '00 IRR='
pending_text db '00 IRQ='
irq_text db '00 EMPTY='
empty_text db '00',13,10
        db 'Silent probe. PIC mask and IRQ vector restored.',13,10
message_end:
        db '$'
