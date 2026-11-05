; SPDX-License-Identifier: GPL-3.0-or-later
; FDREAD.COM: INT 1Bh calls on the 1 MB interface, drive 2 (DA/UA 91h), as a
; 2HD game's IPL makes them (Genesis reads C0 H0 R5 N3 with AH=56h). Prints
; "AH C H R N bytes -> status CX DX | ST0 ST1 ST2 C H R N" per call; the
; result bytes are the BIOS copy at 0000:0564h + unit * 8.
bits 16
cpu 186
org 100h
WS equ 7000h
UNIT equ 1
    mov ah,9
    mov dx,banner
    int 21h
    mov si,calls
.next:
    cmp byte [si],0
    je .done
    push si
    push ds
    xor ax,ax                   ; clear the stored results first
    mov ds,ax
    mov di,0564h + UNIT * 8
    mov cx,8
.clr:
    mov byte [di],0EEh
    inc di
    loop .clr
    pop ds
    mov ax,WS
    mov es,ax
    xor bp,bp
    mov ah,[si]                 ; command
    mov al,90h + UNIT
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
    mov al,'|'
    call putc
    push ds                     ; copy the stored results next to the program
    push es
    push ds
    pop es
    mov di,res
    xor ax,ax
    mov ds,ax
    mov si,0564h + UNIT * 8
    mov cx,7
    rep movsb
    pop es
    pop ds
    mov si,res
    mov cx,7
.res:
    mov al,' '
    call putc
    lodsb
    call hex8
    loop .res
    mov dx,crlf
    mov ah,9
    int 21h
    pop si
    add si,7
    jmp .next
.done:
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
    dw 0                        ; READ ID, MFM, head 0
    db 56h, 0,0,1,3
    dw 400h                     ; C0 H0 R1 (the boot read)
    db 56h, 0,0,5,3
    dw 400h                     ; C0 H0 R5 (Genesis's IPL read)
    db 46h, 0,0,5,3
    dw 400h                     ; the same without the seek bit
    db 56h, 0,0,2,3
    dw 400h                     ; R2
    db 56h, 0,0,8,3
    dw 400h                     ; R8
    db 56h, 0,0,1,3
    dw 2000h                    ; the whole track, R1-R8
    db 4Ah, 0,1,0,0
    dw 0                        ; READ ID, head 1 (IDs say C1 H0)
    db 4Ah, 0,0,0,0
    dw 0                        ; READ ID, head 0 again
    db 56h, 0,0,5,3
    dw 400h                     ; R5 again
    db 0

banner  db 'FDREAD: 1 MB interface, drive 2 (91h). AH C H R N bytes -> status CX DX | ST0 ST1 ST2 C H R N',13,10,'$'
arrow   db ' -> $'
crlf    db 13,10,'$'
st      db 0
ret_cx  dw 0
ret_dx  dw 0
res     times 7 db 0
