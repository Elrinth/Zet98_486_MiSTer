; SPDX-License-Identifier: GPL-3.0-or-later
; EGCSHIFT.COM -- run from a text DOS prompt with EGCVECT.BIN alongside.
; Tests all 512 EGC word alignments/directions, two rows without reloading,
; partial-word clipping, priming and four-plane carry with synthetic pixels.
; Destructive only to graphics VRAM. Leaves GRCG and EGC disabled.
bits 16
cpu 386
org 100h
start:
    cld
    push cs
    pop ds
    mov dx,title
    call puts
    mov dx,filename
    mov ax,3d00h
    int 21h
    jc io_fail
    mov [handle],ax
    mov al,07h
    out 6ah,al
    mov al,01h                 ; 16-color graphics: expose plane E
    out 6ah,al
    mov al,05h                 ; EGC enabled; GRCG gates actual transfers
    out 6ah,al
    xor al,al
    out 7ch,al
next_case:
    mov bx,[handle]
    mov dx,buffer
    mov cx,200
    mov ah,3fh
    int 21h
    jc io_fail
    test ax,ax
    jz finished
    cmp ax,200
    jne io_fail
    mov dx,04a0h
    mov ax,0fff0h              ; all four planes writable
    out dx,ax
    add dx,2
    mov ax,00ffh
    out dx,ax
    add dx,2
    mov ax,28f0h               ; read raw word, latch shifted VRAM source, S copy
    out dx,ax
    add dx,2
    xor ax,ax
    out dx,ax
    add dx,2
    mov ax,[buffer+6]
    out dx,ax
    add dx,2
    xor ax,ax
    out dx,ax
    add dx,2
    mov ax,[buffer]
    out dx,ax
    add dx,2
    mov ax,[buffer+2]
    out dx,ax
    mov bp,[buffer+4]
    mov si,buffer+8
    mov word [step_number],0
next_step:
    xor bx,bx
initialize_planes:
    mov es,[segments+bx]
    mov ax,[si+bx]
    mov [es:0],ax
    mov ax,[si+bx+8]
    mov [es:0200h],ax
    add bx,2
    cmp bx,8
    jb initialize_planes
    mov ax,0a800h
    mov es,ax
    mov al,0c0h
    out 7ch,al
    mov ax,[es:0]
    mov word [es:0200h],0ffffh
    xor al,al
    out 7ch,al
    xor bx,bx
check_planes:
    mov es,[segments+bx]
    mov ax,[es:0200h]
    cmp ax,[si+bx+16]
    jne mismatch
    inc word [checks]
    add bx,2
    cmp bx,8
    jb check_planes
    add si,24
    inc word [step_number]
    dec bp
    jnz next_step
    inc word [cases]
    jmp next_case
finished:
    cmp word [cases],512
    jne io_fail
    call disable
    mov bx,[handle]
    mov ah,3eh
    int 21h
    mov dx,passed
    call puts
    mov ax,[checks]
    call hex
    mov dx,ending
    call puts
    mov ax,4c00h
    int 21h
mismatch:
    mov [actual],ax
    mov ax,[si+bx+16]
    mov [expected],ax
    shr bx,1
    mov [plane],bx
    call disable
    mov dx,failed
    call puts
    mov ax,[cases]
    call hex
    mov dx,step_text
    call puts
    mov ax,[step_number]
    call hex
    mov dx,plane_text
    call puts
    mov ax,[plane]
    call hex
    mov dx,got_text
    call puts
    mov ax,[actual]
    call hex
    mov dx,want_text
    call puts
    mov ax,[expected]
    call hex
    mov dx,newline
    call puts
    mov ax,4c01h
    int 21h
io_fail:
    call disable
    mov dx,io_error
    call puts
    mov ax,4c02h
    int 21h
disable:
    xor al,al
    out 7ch,al
    mov al,07h
    out 6ah,al
    mov al,04h
    out 6ah,al
    mov al,06h
    out 6ah,al
    ret
puts:
    mov ah,09h
    int 21h
    ret
hex:
    pusha
    mov bx,ax
    mov cx,4
.digit:
    rol bx,4
    mov dl,bl
    and dl,15
    add dl,'0'
    cmp dl,'9'
    jbe .print
    add dl,7
.print:
    mov ah,02h
    int 21h
    loop .digit
    popa
    ret
title db 'EGCSHIFT: two-row four-plane graphics alignment test',13,10,'$'
filename db 'EGCVECT.BIN',0
passed db 'PASS: 512 alignments; ','$'
ending db 'h plane checks',13,10,'$'
failed db 'FAIL case $'
step_text db ' step $'
plane_text db ' plane $'
got_text db ' got $'
want_text db ' expected $'
io_error db 'FAIL: vector file missing, truncated, or wrong case count',13,10,'$'
newline db 13,10,'$'
segments dw 0a800h,0b000h,0b800h,0e000h
handle dw 0
cases dw 0
checks dw 0
step_number dw 0
actual dw 0
expected dw 0
plane dw 0
buffer times 200 db 0
