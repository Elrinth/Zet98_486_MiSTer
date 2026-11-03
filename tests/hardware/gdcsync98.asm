; SPDX-License-Identifier: GPL-3.0-or-later
; GDCSYNC.COM: the graphics GDC's SYNC command must switch the display like
; BCTRL does (uPD7220: SYNC 0Fh = display enabled, 0Eh = disabled). Draws a
; white band across the middle of the graphics screen, then steps through
; four commands, waiting for a key after each so the screen can be checked:
;   1: BCTRL 0Dh -> band visible
;   2: SYNC  0Eh -> band hidden
;   3: SYNC  0Fh -> band visible   (B273 and older: stays hidden)
;   4: BCTRL 0Ch -> band hidden
; The SYNCs carry no parameters, as Libros de Chilam Balam sends them.
bits 16
cpu 186
org 100h
    mov ah,42h                  ; 640x400, page 0
    mov ch,0C0h
    int 18h
    mov ah,40h                  ; graphics display on (BIOS)
    int 18h
    ; known state whatever ran before: GRCG off, EGC off, analog palette with
    ; colour 7 white, display and access page 0
    xor al,al
    out 7Ch,al                  ; GRCG off
    mov al,07h
    out 6Ah,al                  ; mode change allowed
    mov al,04h
    out 6Ah,al                  ; EGC off (GRCG-compatible)
    mov al,06h
    out 6Ah,al                  ; mode change locked
    mov al,01h
    out 6Ah,al                  ; 16-colour analog palette
    xor al,al
    out 0A4h,al                 ; display page 0
    out 0A6h,al                 ; access page 0
    mov al,7
    out 0A8h,al                 ; palette index 7
    mov al,0Fh
    out 0AAh,al                 ; green
    out 0ACh,al                 ; red
    out 0AEh,al                 ; blue
    ; band: rows 150-249 of the B, R and G planes = 0FFh (colour 7)
    mov cx,3
    mov si,planes
.plane:
    push cx
    mov es,[si]
    mov di,150*80
    mov cx,100*80/2
    mov ax,0FFFFh
    rep stosw
    add si,2
    pop cx
    loop .plane
    mov al,0Dh
    mov dx,msg1
    call step
    mov al,0Eh
    mov dx,msg2
    call step
    mov al,0Fh
    mov dx,msg3
    call step
    mov al,0Ch
    mov dx,msg4
    call step
    mov ax,4C00h
    int 21h

; AL = GDC command for port A2h, DX = message; then wait for a key
step:
    push ax
.wait:
    in al,0A0h                  ; graphics GDC status: bit 1 = FIFO full
    test al,2
    jnz .wait
    pop ax
    out 0A2h,al
    mov ah,9
    int 21h
    mov ah,8                    ; wait for a key (no echo)
    int 21h
    ret

planes  dw 0A800h, 0B000h, 0B800h
msg1    db 'GDCSYNC 1: BCTRL 0Dh - band visible. Key...',13,10,'$'
msg2    db 'GDCSYNC 2: SYNC 0Eh - band hidden. Key...',13,10,'$'
msg3    db 'GDCSYNC 3: SYNC 0Fh - band visible. Key...',13,10,'$'
msg4    db 'GDCSYNC 4: BCTRL 0Ch - band hidden. Key...',13,10,'$'
