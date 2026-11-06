; SPDX-License-Identifier: GPL-3.0-or-later
; P9A8.COM: reads back the PC-9821 31 kHz latch, port 09A8h bit 0, which
; software reads to learn the display rate (Open BIOS INT 18h AH=31h before
; 2026-10-31). Up to B279 the core left 09A8h reads to the open bus (FFh).
; Writes 1 and 0, reads each back, restores the first value (0, 24 kHz, when
; the latch does not read back) and prints
;   09A8h before xx  after 1: xx  after 0: xx  PASS|FAIL
; PASS: bit 0 follows both writes. Writing 1 switches the core to 31 kHz for a
; few microseconds; the monitor may blink.
bits 16
cpu 186
org 100h
    mov dx,09A8h
    in al,dx
    mov [before],al
    cli
    mov al,1
    out dx,al
    in al,dx
    mov [after1],al
    xor al,al
    out dx,al
    in al,dx
    mov [after0],al
    xor al,al
    test byte [after1],1
    jz .restore
    test byte [after0],1
    jnz .restore
    mov al,[before]
    and al,1
.restore:
    out dx,al
    sti
    mov al,[before]
    mov di,t_before
    call hex
    mov al,[after1]
    mov di,t_after1
    call hex
    mov al,[after0]
    mov di,t_after0
    call hex
    mov si,fail
    test byte [after1],1
    jz .print
    test byte [after0],1
    jnz .print
    mov si,pass
.print:
    mov ah,9
    mov dx,msg
    int 21h
    mov ah,9
    mov dx,si
    int 21h
    mov ax,4C00h
    int 21h

; AL as two hex digits at DI
hex:
    push ax
    shr al,4
    call digit
    pop ax
    and al,0Fh
digit:
    add al,'0'
    cmp al,'9'
    jbe .store
    add al,7
.store:
    mov [di],al
    inc di
    ret

before:     db 0
after1:     db 0
after0:     db 0
msg:        db '09A8h before '
t_before:   db '00  after 1: '
t_after1:   db '00  after 0: '
t_after0:   db '00  $'
pass:       db 'PASS',13,10,'$'
fail:       db 'FAIL',13,10,'$'
