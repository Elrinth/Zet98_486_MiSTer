; SPDX-License-Identifier: GPL-3.0-or-later
; Live input probe for games that poll input directly (Mime's STSSP menu):
; shows on text row 0 the BIOS key-state bitmap 0000:052A-0539, and, when the
; drivers are resident, STMD INT 68h AH=09h (buttons) / AH=05h (area in DX)
; and PMD INT 60h AH=16h (joystick, active low). Row 1 counts loop passes.
; Each pass also writes the values to ports 7F00h+index (0-15 bitmap, 16 buttons,
; 17/18 area DH/DL, 19 joystick, 20-23 INT 09h vector, 24-39 bitmap ORed over
; the whole pass while it waits, 40-45 key buffer head/tail/count/error count
; at 0000:0524-0529, 46 IMR, 47 IRR, 48 ISR of the master PIC, 49 8251 status) with a pause after each, so a trace build's
; periodic "last I/O" sample shows them when the screen cannot be read.
; Exits after about 30 seconds (BIOS tick-free counter) or on ESC (bitmap).
bits 16
cpu 8086
org 100h
start:
    cld
    mov ax,0a000h
    mov es,ax                  ; text VRAM
    mov word [passes],0
    mov word [passes+2],0
.loop:
    push ds                    ; copy the bitmap first
    xor ax,ax
    mov ds,ax
    mov si,052ah
    mov di,bitmap
    push cs
    pop es
    mov cx,8
    rep movsw
    pop ds
    mov ax,0a000h
    mov es,ax
    xor di,di                  ; row 0: "K" + 16 bitmap bytes
    mov al,'K'
    call putc
    mov si,bitmap
    mov cx,16
.bm:
    lodsb
    call puthex
    mov al,' '
    call putc
    loop .bm
    ; row 0, column 56: mouse and joystick when their vectors are set
    mov di,56*2
    mov al,'M'
    call putc
    mov bx,68h*4
    call vector_set
    jz .nomouse
    mov ah,9
    int 68h
    call vram
    mov [bitmap+16],al
    call puthex
    mov al,' '
    call putc
    mov ah,5
    int 68h
    call vram
    mov [bitmap+17],dh
    mov [bitmap+18],dl
    mov al,dh
    call puthex
    mov al,dl
    call puthex
    jmp .joy
.nomouse:
    mov al,'-'
    call putc
.joy:
    mov al,' '
    call putc
    mov al,'J'
    call putc
    mov bx,60h*4
    call vector_set
    jz .nojoy
    mov ah,16h
    int 60h
    call vram
    mov [bitmap+19],al
    call puthex
    jmp .row1
.nojoy:
    mov al,'-'
    call putc
.row1:
    mov di,80*2                ; row 1: pass counter
    mov al,'P'
    call putc
    add word [passes],1
    adc word [passes+2],0
    mov al,[passes+3]
    call puthex
    mov al,[passes+2]
    call puthex
    mov al,[passes+1]
    call puthex
    ; INT 09h vector
    push ds
    xor ax,ax
    mov ds,ax
    mov ax,[9*4]
    mov bx,[9*4+2]
    pop ds
    mov [bitmap+20],ax
    mov [bitmap+22],bx
    push ds
    xor ax,ax
    mov ds,ax
    mov si,0524h
    mov di,bitmap+40
    push cs
    pop es
    mov cx,6
    rep movsb
    pop ds
    in al,02h
    mov [bitmap+46],al
    cli
    mov al,0ah
    out 00h,al
    in al,00h
    mov [bitmap+47],al
    mov al,0bh
    out 00h,al
    in al,00h
    mov [bitmap+48],al
    mov al,0ah
    out 00h,al
    sti
    in al,43h
    mov [bitmap+49],al
    ; report every value on its own port; while pausing after each, OR the
    ; live bitmap into the sticky copy (reported next pass)
    mov si,bitmap
    mov dx,7f00h
    mov cx,50
.report:
    lodsb
    out dx,al
    push cx
    mov cx,30000
.pause:
    push ds
    push si
    push cx
    xor ax,ax
    mov ds,ax
    mov si,052ah
    mov bx,sticky
    mov cx,16
.or:
    lodsb
    or [cs:bx],al
    inc bx
    loop .or
    pop cx
    pop si
    pop ds
    loop .pause
    pop cx
    inc dx
    loop .report
    ; the sticky copy becomes the reported one; start a new one
    push ds
    pop es
    mov si,sticky
    mov di,bitmap+24
    mov cx,8
    rep movsw
    mov di,sticky
    xor ax,ax
    mov cx,8
    rep stosw
    mov ax,0a000h
    mov es,ax
    ; ESC (scancode 00h) in the bitmap, or about 2 M passes
    push ds
    xor ax,ax
    mov ds,ax
    test byte [052ah],1
    pop ds
    jnz .done
    cmp word [passes],90
    jb .loop
.done:
    mov ax,4c00h
    int 21h

; ZF=1 when the interrupt vector at 0000:BX is zero
vector_set:
    push ds
    xor ax,ax
    mov ds,ax
    mov ax,[bx]
    or ax,[bx+2]
    pop ds
    ret

; text VRAM: characters at even words (JIS/ASCII), attributes at A200h
putc:
    xor ah,ah
    stosw
    ret

; the drivers may change ES: point it back at text VRAM (keeps AX, DI)
vram:
    push ax
    mov ax,0a000h
    mov es,ax
    pop ax
    ret

puthex:
    push ax
    push cx
    mov cl,4
    mov ah,al
    shr al,cl
    call nib
    mov al,ah
    and al,0fh
    call nib
    pop cx
    pop ax
    ret
nib:
    add al,'0'
    cmp al,'9'
    jbe .ok
    add al,7
.ok:
    push ax
    call putc
    pop ax
    ret

passes: dw 0,0
bitmap: times 16 db 0
values: times 8 db 0ffh
        times 16 db 0
kbuf:   times 10 db 0           ; bitmap+40
sticky: times 16 db 0
