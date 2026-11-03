; SPDX-License-Identifier: GPL-3.0-or-later
; FD2DD.COM: INT 1Bh on the 640 KB interface with a 2DD disk (16 x 256-byte
; MFM sectors per track, as Sorcerian) in drive 2. Selects the interface with
; OUT BEh,00h like a 2DD boot, then runs the calls Sorcerian's IPL makes and a
; few around them, printing "AH AL C H R N bytes -> status" for each. The 1 MB
; interface is selected again at the end.
bits 16
cpu 186
org 100h
WS equ 7000h
    mov ah,9
    mov dx,banner
    int 21h
    xor al,al
    out 0BEh,al                 ; 640 KB interface
    mov si,calls
.next:
    cmp byte [si],0
    je .done
    push si
    mov ax,WS
    mov es,ax
    xor bp,bp
    mov ah,[si]                 ; command
    mov al,71h                  ; 640 KB interface, unit 1
    mov cl,[si+1]               ; C
    mov dh,[si+2]               ; H
    mov dl,[si+3]               ; R
    mov ch,[si+4]               ; N
    mov bx,[si+5]               ; bytes
    push ax
    push cx
    push dx
    push bx
    int 1Bh
    mov [st],ah
    mov [ret_cx],cx
    mov [ret_dx],dx
    pop bx
    pop dx
    pop cx
    pop ax
    call hex8sp_ah              ; AH
    call hex8sp                 ; AL
    mov al,cl
    call hex8sp
    mov al,dh
    call hex8sp
    mov al,dl
    call hex8sp
    mov al,ch
    call hex8sp
    mov ax,bx
    call hex16
    mov dx,arrow
    mov ah,9
    int 21h
    mov al,[st]
    call hex8sp
    mov ax,[ret_cx]             ; READ ID: CL=C, CH=N, DH=H, DL=R
    call hex16
    mov al,' '
    call putc
    mov ax,[ret_dx]
    call hex16
    mov dx,crlf
    mov ah,9
    int 21h
    pop si
    add si,7
    jmp .next
.done:
    mov al,03h
    out 0BEh,al                 ; back to the 1 MB interface
    mov ax,4C00h
    int 21h

hex8sp_ah:
    push ax
    mov al,ah
    call hex8sp
    pop ax
    ret
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
hex8sp:
    call hex8
    push ax
    mov al,' '
    call putc
    pop ax
    ret
nib:
    push ax
    add al,'0'
    cmp al,'9'
    jbe .p
    add al,7
.p: call putc
    pop ax
    ret
putc:
    push ax
    push dx
    mov dl,al
    mov ah,2
    int 21h
    pop dx
    pop ax
    ret

; AH, C, H, R, N, bytes (word)
calls:
    db 07h, 0,0,0,0
    dw 0                        ; recalibrate
    db 4Ah, 0,0,0,0
    dw 0                        ; READ ID, MFM
    db 56h, 0,0,1,1
    dw 200h                     ; read 512 bytes C0 H0 (the boot read)
    db 56h, 0,0,1,1
    dw 1000h                    ; read a whole track C0 H0 (16 sectors)
    db 10h, 1,0,0,1
    dw 0                        ; seek C1
    db 4Ah, 1,0,0,0
    dw 0                        ; READ ID at C1
    db 56h, 1,0,1,1
    dw 200h                     ; read 512 bytes C1 H0
    db 56h, 1,0,1,1
    dw 1000h                    ; read a whole track C1 H0 (the IPL's first read)
    db 56h, 1,1,1,1
    dw 1000h                    ; C1 H1
    db 56h, 4,0,1,1
    dw 1000h                    ; C4 H0
    db 0

banner  db 'FD2DD: 640 KB interface, drive 2 (71h). AH AL C H R N bytes -> status CX DX',13,10,'$'
arrow   db ' -> $'
crlf    db 13,10,'$'
st      db 0
ret_cx  dw 0
ret_dx  dw 0
