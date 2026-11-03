; SPDX-License-Identifier: GPL-3.0-or-later
; MOUSEBTN.COM: the bus mouse buttons as two kinds of game code see them, 15
; seconds each; click and hold the buttons during both phases.
;  1. Interrupt driver (MOUSE.COM style, Tanjou Debut): IR13 (INT 15h) at
;     120 Hz with port C = 00h; the handler reads port A. Shows
;       IRQ   interrupts taken
;       A     last port A value seen in the handler (bit 7 left, bit 5 right, 0 = down)
;       Li Ri handler samples with the left / right button down
;       Lp Rp presses (down edges) seen by polling port A in the main loop
;  2. Latched polling (Tenbu Sangokushi): mouse interrupt off, each sample
;     writes port C 90h, B0h, D0h, F0h (latch held) and reads port A after each;
;     the buttons come from the fourth read. Shows
;       S     samples
;       B     last fourth read
;       Lt Rt presses seen this way
; Both games took clicks in NP2kai but not on the core.
bits 16
cpu 186
org 100h
    mov ah,9
    mov dx,banner
    int 21h
    xor ax,ax
    mov es,ax
    cli
    mov ax,[es:15h*4]
    mov [old15],ax
    mov ax,[es:15h*4+2]
    mov [old15+2],ax
    mov word [es:15h*4],handler
    mov [es:15h*4+2],cs
    mov dx,7FDFh
    mov al,93h                  ; 8255: A in, B in, C upper out, C lower in
    out dx,al
    mov dx,7FDDh
    xor al,al                   ; PC4 = 0: mouse interrupt on, HC = 0
    out dx,al
    mov dx,0BFDBh
    xor al,al                   ; 120 Hz
    out dx,al
    in al,0Ah
    mov [oldimr],al
    and al,0DFh                 ; unmask IR13
    out 0Ah,al
    sti
    call seconds
    mov [t0],al
    mov byte [prev],0A0h
.loop1:
    mov dx,7FD9h
    in al,dx
    mov ah,[prev]
    mov [prev],al
    test al,80h
    jnz .nl
    test ah,80h
    jz .nl
    inc word [lpoll]
.nl:
    test al,20h
    jnz .nr
    test ah,20h
    jz .nr
    inc word [rpoll]
.nr:
    inc word [spin]
    test word [spin],3FFFh
    jnz .loop1
    call status1
    call elapsed
    cmp al,15
    jb .loop1
    ; phase 2: interrupt off, latched polling
    cli
    mov al,[oldimr]
    out 0Ah,al
    xor ax,ax
    mov es,ax
    mov ax,[old15]
    mov [es:15h*4],ax
    mov ax,[old15+2]
    mov [es:15h*4+2],ax
    sti
    call status1
    mov ah,9
    mov dx,crlf
    int 21h
    mov byte [prev],0A0h
.loop2:
    mov dx,7FDDh
    mov al,90h
    out dx,al
    mov dx,7FD9h
    in al,dx
    mov dx,7FDDh
    mov al,0B0h
    out dx,al
    mov dx,7FD9h
    in al,dx
    mov dx,7FDDh
    mov al,0D0h
    out dx,al
    mov dx,7FD9h
    in al,dx
    mov dx,7FDDh
    mov al,0F0h
    out dx,al
    mov dx,7FD9h
    in al,dx
    mov [last4],al
    mov dx,7FDDh
    mov al,10h                  ; HC = 0, interrupt still off
    out dx,al
    inc word [samples]
    mov ah,[prev]
    mov [prev],al
    test al,80h
    jnz .tl
    test ah,80h
    jz .tl
    inc word [ltn]
.tl:
    test al,20h
    jnz .tr
    test ah,20h
    jz .tr
    inc word [rtn]
.tr:
    mov cx,400h                 ; about 30 ms between samples on the core
.w: loop .w
    test word [samples],0Fh
    jnz .loop2
    call status2
    call elapsed
    cmp al,30
    jb .loop2
    mov dx,7FDDh
    xor al,al                   ; leave the port as the BIOS had it
    out dx,al
    call status2
    mov ah,9
    mov dx,crlf
    int 21h
    mov ax,4C00h
    int 21h

handler:
    push ax
    push dx
    push ds
    mov ax,cs
    mov ds,ax
    inc word [irqs]
    mov dx,7FD9h
    in al,dx
    mov [lasta],al
    test al,80h
    jnz .hl
    inc word [lirq]
.hl:
    test al,20h
    jnz .hr
    inc word [rirq]
.hr:
    mov al,20h
    out 08h,al                  ; EOI slave
    mov al,0Bh
    out 08h,al
    in al,08h
    test al,al
    jnz .hd
    mov al,20h
    out 00h,al                  ; EOI master
.hd:
    pop ds
    pop dx
    pop ax
    iret

; AL = DOS clock seconds
seconds:
    mov ah,2Ch
    int 21h
    mov al,dh
    ret
; AL = seconds since t0
elapsed:
    call seconds
    sub al,[t0]
    jnc .pos
    add al,60
.pos:
    ret

status1:
    mov ah,9
    mov dx,cr
    int 21h
    mov dx,s_irq
    mov ax,[irqs]
    call field
    mov dx,s_a
    mov ah,9
    int 21h
    mov al,[lasta]
    call hex8
    mov dx,s_li
    mov ax,[lirq]
    call field
    mov dx,s_ri
    mov ax,[rirq]
    call field
    mov dx,s_lp
    mov ax,[lpoll]
    call field
    mov dx,s_rp
    mov ax,[rpoll]
    call field
    ret

status2:
    mov ah,9
    mov dx,cr
    int 21h
    mov dx,s_s
    mov ax,[samples]
    call field
    mov dx,s_b
    mov ah,9
    int 21h
    mov al,[last4]
    call hex8
    mov dx,s_lt
    mov ax,[ltn]
    call field
    mov dx,s_rt
    mov ax,[rtn]
    call field
    ret

; print the $-string at DX, then AX in hex
field:
    push ax
    mov ah,9
    int 21h
    pop ax
hex16:
    push ax
    mov al,ah
    call hex8
    pop ax
hex8:
    push ax
    shr al,4
    call nib
    pop ax
    push ax
    and al,0Fh
    call nib
    pop ax
    ret
nib:
    push ax
    push dx
    add al,'0'
    cmp al,'9'
    jbe .p
    add al,7
.p: mov dl,al
    mov ah,2
    int 21h
    pop dx
    pop ax
    ret

banner  db 'MOUSEBTN: 15 s IR13 driver, then 15 s latched polling; click and hold.',13,10,'$'
s_irq   db 'IRQ $'
s_a     db ' A $'
s_li    db ' Li $'
s_ri    db ' Ri $'
s_lp    db ' Lp $'
s_rp    db ' Rp $'
s_s     db 'S $'
s_b     db ' B $'
s_lt    db ' Lt $'
s_rt    db ' Rt $'
cr      db 13,'$'
crlf    db 13,10,'$'
old15   dd 0
oldimr  db 0
t0      db 0
prev    db 0
lasta   db 0
last4   db 0
irqs    dw 0
lirq    dw 0
rirq    dw 0
lpoll   dw 0
rpoll   dw 0
spin    dw 0
samples dw 0
ltn     dw 0
rtn     dw 0
