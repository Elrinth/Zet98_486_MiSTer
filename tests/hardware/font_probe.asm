; SPDX-License-Identifier: GPL-3.0-or-later
; PC-98 DOS CG-ROM read probe. Creates a NEW Z98FONT.BIN; never overwrites.
; Each record contains A1:A3 and 32 pairs of immediate/delayed A9 reads.
; Positions 0..15 select A5=20..2f; positions 16..31 select A5=00..0f.
; IMMEDIATE_IO uses adjacent immediate OUT/IN instructions as Rusty does.
bits 16
cpu 8086
org 100h
start:
    push cs
    pop ds
    push cs
    pop es
    cld
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,filename
    mov ax,5b00h
    xor cx,cx
    int 21h
    jc failed
    mov [handle],ax
    mov si,codes
    mov di,records
    mov bp,CODE_COUNT
.glyph:
    pushf
    cli
%ifdef IMMEDIATE_IO
    mov al,0bh
    out 68h,al
%endif
    lodsw
    stosw
    mov dx,0a1h
    xchg al,ah
%ifdef IMMEDIATE_IO
    out 0a1h,al
%else
    out dx,al
%endif
    add dx,2
    mov al,ah
%ifdef IMMEDIATE_IO
    out 0a3h,al
%else
    out dx,al
%endif
    xor bx,bx
.row:
    mov al,bl
    and al,15
    test bl,16
    jnz .right
    or al,20h
.right:
%ifdef IMMEDIATE_IO
    out 0a5h,al
    in al,0a9h
%else
    mov dx,0a5h
    out dx,al
    mov dx,0a9h
    in al,dx
%endif
    stosb
    times 8 nop
%ifdef IMMEDIATE_IO
    in al,0a9h
%else
    in al,dx
%endif
    stosb
    inc bl
    cmp bl,32
    jb .row
%ifdef IMMEDIATE_IO
    mov al,0ah
    out 68h,al
%endif
    popf
    dec bp
    jnz .glyph
    mov bx,[handle]
    mov dx,capture
    mov cx,CAPTURE_SIZE
    mov ah,40h
    int 21h
    jc close_failed
    cmp ax,CAPTURE_SIZE
    jne close_failed
    mov bx,[handle]
    mov ah,3eh
    int 21h
    jc failed
    mov ah,0dh
    int 21h
    mov dx,success_text
    mov ah,9
    int 21h
    xor al,al
    jmp finish
close_failed:
    mov bx,[handle]
    mov ah,3eh
    int 21h
failed:
    mov dx,failure_text
    mov ah,9
    int 21h
    mov al,1
finish:
%ifdef PROBE_SHELL
    sti
.halt:
    hlt
    jmp .halt
%else
    mov ah,4ch
    int 21h
%endif
critical_error:
    mov al,3
    iret
handle: dw 0
filename: db 'Z98FONT.BIN',0
success_text: db 'Font capture saved to Z98FONT.BIN.',13,10,'$'
failure_text: db 'Font capture failed (existing file or disk error).',13,10,'$'
codes:
    dw 0053h,0020h,0043h
    dw 2009h,4309h,4f09h,5309h,6109h,6509h,6909h
    dw 6e09h,6f09h,7009h,7209h,7309h,7409h,7509h
    dw 2101h,5308h,530ah,530bh,530ch,535ch
codes_end:
CODE_COUNT equ (codes_end-codes)/2
capture:
    db 'Z98FONT2'
    dw CODE_COUNT
records: times CODE_COUNT*66 db 0
CAPTURE_SIZE equ $-capture
