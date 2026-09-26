; SPDX-License-Identifier: GPL-3.0-or-later
; Read-only PC-98 machine-identification evidence. No driver/game code.
; Reports two independent inputs used by stock HIMEM's CPU admission check.
; Does NOT change BIOS identification bytes or force the driver to load.
; Redirect stdout to a NEW file on a disposable disk if a file is needed.
bits 16
cpu 386
org 100h
start:
    push cs
    pop ds
    pushf
    pop bx
    xor ax,ax
    push ax
    popf
    pushf
    pop ax
    push bx
    popf                         ; restore caller IF/flags before any DOS call
    mov [flags_zero],ax
    cld                          ; caller DF may be set; output walks forward
    xor ax,ax
    mov es,ax
    mov al,[es:0480h]
    mov [system_type],ax
    mov al,[es:0500h]
    mov [bios_flag0],ax
    mov al,[es:0501h]
    mov [bios_flag1],ax
    mov dx,title
    call puts
    mov si,labels
    mov di,values
    mov cx,4
.field:
    lodsw
    mov dx,ax
    call puts
    mov ax,[di]
    call hex16
    add di,2
    mov dx,newline
    call puts
    loop .field
    mov dx,cpu_reject
    call puts
    mov ax,[flags_zero]
    and ax,0f000h
    cmp ax,0f000h
    mov ax,0
    jne .cpu_done
    inc ax
.cpu_done:
    call hex16
    mov dx,bios_reject
    call puts
    mov ax,[bios_flag1]
    and ax,40h
    shr ax,6
    call hex16
    mov dx,newline
    call puts
    mov ax,4c00h
    int 21h
puts:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov ah,9
    int 21h
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
hex16:
    push ax
    push bx
    push cx
    push dx
    mov bx,ax
    mov cx,4
.digit:
    rol bx,4
    mov dl,bl
    and dl,15
    add dl,'0'
    cmp dl,'9'
    jbe .emit
    add dl,7
.emit:
    mov ah,2
    int 21h
    loop .digit
    pop dx
    pop cx
    pop bx
    pop ax
    ret
title: db 'PC-98 identity probe R1 (hex values; BIOS read-only)',13,10,'$'
labels: dw flags_text,type_text,flag0_text,flag1_text
values:
flags_zero: dw 0
system_type: dw 0
bios_flag0: dw 0
bios_flag1: dw 0
flags_text: db 'FLAGS after POPF(0) = $'
type_text: db 'BIOS 0000:0480 = $'
flag0_text: db 'BIOS 0000:0500 = $'
flag1_text: db 'BIOS 0000:0501 = $'
cpu_reject: db '8086 FLAGS rejection = $'
bios_reject: db ' / BIOS bit40 rejection = $'
newline: db 13,10,'$'
