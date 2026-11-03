; SPDX-License-Identifier: GPL-3.0-or-later
; FDVRAM.COM: floppy write DMA from each memory kind. Writes a 1024-byte
; pattern (consecutive bytes differ) to cylinder 10, head 0, sector 1 of the
; 2HD disk in drive 2 (INT 1Bh DA/UA 91h) from conventional RAM, from graphics
; VRAM (B000:0000) and from text VRAM (A000:0000, even bytes are codes), reads
; each back into RAM and compares. A DMA path that returns the even byte for
; odd addresses writes every even byte twice.
; Output per source: OK, or the first bad offset with the bytes read back.
; The disk in drive 2 is overwritten (use a scratch disk).
bits 16
cpu 486
org 100h
SECTOR equ 1024
WS equ 7000h                    ; work segment inside the program's memory block:
PAT equ 0                       ; pattern and read-back buffer never cross a
RBUF equ 800h                   ; 64 KB DMA boundary there
    mov ah,9
    mov dx,banner
    int 21h
    ; pattern: byte i = i*7 + (i >> 8)
    mov ax,WS
    mov es,ax
    mov di,PAT
    xor bx,bx
.fill:
    mov ax,bx
    imul ax,ax,7
    mov cx,bx
    shr cx,8
    add al,cl
    mov [es:di+bx],al
    inc bx
    cmp bx,SECTOR
    jb .fill
    ; 1: conventional RAM
    mov ax,WS
    mov es,ax
    mov bp,PAT
    mov dx,msg_ram
    call test_one
    ; 2: graphics VRAM plane at B000:0000 (GRCG off)
    mov ax,0B000h
    call copy_to_seg
    mov ax,0B000h
    mov es,ax
    xor bp,bp
    mov dx,msg_gvram
    call test_one
    ; 3: text VRAM at A000:0000 (only the low bytes of each word are stored
    ; as written; compare the even offsets only through the same test)
    mov ax,0A000h
    call copy_to_seg
    mov ax,0A000h
    mov es,ax
    xor bp,bp
    mov dx,msg_tvram
    call test_one
    mov ax,4C00h
    int 21h

; copy the pattern to AX:0000
copy_to_seg:
    push ds
    push es
    mov es,ax
    mov ax,WS
    mov ds,ax
    mov si,PAT
    xor di,di
    mov cx,SECTOR
    cld
    rep movsb
    pop es
    pop ds
    ret

; write ES:BP, read back into WS:RBUF, compare with the source at ES:BP.
; DX = name string.
test_one:
    mov [src_seg],es
    mov [src_off],bp
    mov ah,9
    int 21h
    ; write
    mov ax,5591h                ; WRITE DATA, MFM, seek; 1 MB drive unit 1
    mov bx,SECTOR
    mov cx,030Ah                ; N = 3, C = 10
    mov dx,0001h                ; H = 0, R = 1
    int 1Bh
    jc .write_err
    ; read back
    mov ax,WS
    mov es,ax
    mov bp,RBUF
    mov ax,5691h                ; READ DATA
    mov bx,SECTOR
    mov cx,030Ah
    mov dx,0001h
    int 1Bh
    jc .read_err
    ; compare the read-back with the source, byte by byte
    mov ax,WS
    mov es,ax
    push ds
    mov si,[src_off]
    mov ax,[src_seg]
    mov ds,ax
    xor bx,bx
.cmp:
    mov al,[si+bx]
    cmp al,[es:RBUF+bx]
    jne .bad
    inc bx
    cmp bx,SECTOR
    jb .cmp
    pop ds
    mov dx,msg_ok
    mov ah,9
    int 21h
    ret
.bad:
    pop ds
    mov [bad_off],bx
    mov dx,msg_bad
    mov ah,9
    int 21h
    mov ax,[bad_off]
    call hex16
    mov dx,msg_got
    mov ah,9
    int 21h
    ; 8 bytes read back from the bad offset (rounded down to even)
    mov si,[bad_off]
    and si,0FFFEh
    mov cx,8
.g: push es
    mov ax,WS
    mov es,ax
    mov al,[es:RBUF+si]
    pop es
    call hex8sp
    inc si
    loop .g
    mov dx,msg_want
    mov ah,9
    int 21h
    mov si,[bad_off]
    and si,0FFFEh
    mov cx,8
    push ds
    mov ax,[src_seg]
    mov bx,[src_off]
    mov ds,ax
.w: mov al,[bx+si]
    call hex8sp
    inc si
    loop .w
    pop ds
    mov dx,crlf
    mov ah,9
    int 21h
    ret
.write_err:
    mov dx,msg_werr
    jmp .err
.read_err:
    mov dx,msg_rerr
.err:
    push ax
    mov ah,9
    int 21h
    pop ax
    mov al,ah
    call hex8sp
    mov dx,crlf
    mov ah,9
    int 21h
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
    push dx
    mov dl,' '
    mov ah,2
    int 21h
    pop dx
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

banner  db 'FDVRAM: INT 1Bh write + read back, drive 2, C10 H0 R1',13,10,'$'
msg_ram db 'RAM    : $'
msg_gvram db 'G-VRAM : $'
msg_tvram db 'T-VRAM : $'
msg_ok  db 'OK',13,10,'$'
msg_bad db 'BAD at $'
msg_got db ' got $'
msg_want db 'want $'
msg_werr db 'write error $'
msg_rerr db 'read error $'
crlf    db 13,10,'$'
src_seg dw 0
src_off dw 0
bad_off dw 0
