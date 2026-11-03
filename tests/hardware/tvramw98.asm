; SPDX-License-Identifier: GPL-3.0-or-later
; TVRAMW.COM: CPU writes into text VRAM with every store width. For each of
; STOSB, STOSW, STOSD, MOVSB, MOVSW, MOVSD and single dword stores at odd
; addresses it fills A000:0000-3FFF (character codes A0000-A1FFF, attributes
; A2000-A3FFF) with a byte pattern, then compares: every code byte, and the
; even (attribute) bytes of A2000-A3FDF (A3FE0-A3FFF are the write-protected
; memory switches). Prints the mismatch counts and the first bad offset per
; method, then writes two attribute words and reads them back as words. Ningyou Tsukai 2 fills this area with data and relies on the
; attribute bytes it wrote (all hidden) - the core showed coloured garbage.
bits 16
cpu 486
org 100h
WS equ 7000h                    ; source buffer segment (16 KB pattern)
    ; pattern into WS:0000-3FFF: b(i) = (i*37 + (i>>8)*11) & 0FFh
    mov ax,WS
    mov es,ax
    xor di,di
.pat:
    mov ax,di
    imul ax,ax,37
    mov bx,di
    shr bx,8
    imul bx,bx,11
    add ax,bx
    stosb
    cmp di,4000h
    jb .pat
    mov si,methods
    mov di,results
.next:
    mov bx,[si]
    test bx,bx
    jz .print
    push si
    push di
    call clear
    call bx                     ; fill A000:0000-3FFF
    call verify                 ; DX = code mismatches, CX = attribute mismatches, BP = first bad
    pop di
    mov [di],dx
    mov [di+2],cx
    mov [di+4],bp
    push di
    call restore
    pop di
    add di,6
    pop si
    add si,4
    jmp .next
.print:                         ; the screen was rewritten by every method: print at the end
    mov si,methods
    mov di,results
.pl:
    cmp word [si],0
    je .words
    push si
    push di
    mov dx,[si+2]
    mov ah,9
    int 21h
    mov ax,[di]
    call hex16
    mov dx,msg_attr
    mov ah,9
    int 21h
    mov ax,[di+2]
    call hex16
    mov dx,msg_first
    mov ah,9
    int 21h
    mov ax,[di+4]
    call hex16
    mov dx,crlf
    mov ah,9
    int 21h
    pop di
    pop si
    add si,4
    add di,6
    jmp .pl
.words:
    ; attribute words: write 5AA5h, 0C33Ch to A2000h/A2002h as words, read back as
    ; words (the upper byte of an attribute word is memory in NP2kai and MAME)
    push es
    mov ax,0A000h
    mov es,ax
    mov word [es:2000h],5AA5h
    mov word [es:2002h],0C33Ch
    mov ax,[es:2000h]
    mov [hw0],ax
    mov ax,[es:2002h]
    mov [hw1],ax
    mov word [es:2000h],00E1h
    mov word [es:2002h],00E1h
    pop es
    mov dx,msg_hi
    mov ah,9
    int 21h
    mov ax,[hw0]
    call hex16
    mov dl,' '
    mov ah,2
    int 21h
    mov ax,[hw1]
    call hex16
    mov dx,crlf
    mov ah,9
    int 21h
.done:
    mov ax,4C00h
    int 21h

; zero the whole 16 KB window
clear:
    push es
    mov ax,0A000h
    mov es,ax
    xor di,di
    xor ax,ax
    mov cx,2000h
    cld
    rep stosw
    pop es
    ret

; blank screen: spaces with attribute E1h
restore:
    push es
    mov ax,0A000h
    mov es,ax
    xor di,di
    mov ax,0020h
    mov cx,1000h
    cld
    rep stosw
    mov di,2000h
    mov ax,00E1h
    mov cx,1000h
    rep stosw
    pop es
    ret

; methods: each fills A000:0000-3FFF from the pattern
m_stosb:
    push ds
    push es
    mov ax,WS
    mov ds,ax
    mov ax,0A000h
    mov es,ax
    xor si,si
    xor di,di
    cld
.l: lodsb
    stosb
    cmp di,4000h
    jb .l
    pop es
    pop ds
    ret
m_stosw:
    push ds
    push es
    mov ax,WS
    mov ds,ax
    mov ax,0A000h
    mov es,ax
    xor si,si
    xor di,di
    cld
.l: lodsw
    stosw
    cmp di,4000h
    jb .l
    pop es
    pop ds
    ret
m_stosd:
    push ds
    push es
    mov ax,WS
    mov ds,ax
    mov ax,0A000h
    mov es,ax
    xor si,si
    xor di,di
    cld
.l: lodsd
    stosd
    cmp di,4000h
    jb .l
    pop es
    pop ds
    ret
m_movsb:
    push ds
    push es
    mov ax,WS
    mov ds,ax
    mov ax,0A000h
    mov es,ax
    xor si,si
    xor di,di
    mov cx,4000h
    cld
    rep movsb
    pop es
    pop ds
    ret
m_movsw:
    push ds
    push es
    mov ax,WS
    mov ds,ax
    mov ax,0A000h
    mov es,ax
    xor si,si
    xor di,di
    mov cx,2000h
    cld
    rep movsw
    pop es
    pop ds
    ret
m_movsd:
    push ds
    push es
    mov ax,WS
    mov ds,ax
    mov ax,0A000h
    mov es,ax
    xor si,si
    xor di,di
    mov cx,1000h
    cld
    rep movsd
    pop es
    pop ds
    ret
; dword stores at odd offsets 1, 5, 9, ... (each spans two words), then the
; leftover first byte and the last three bytes as bytes
m_oddd:
    push ds
    push es
    mov ax,WS
    mov ds,ax
    mov ax,0A000h
    mov es,ax
    mov al,[0]
    mov [es:0],al
    mov si,1
.l: mov eax,[si]
    mov [es:si],eax
    add si,4
    cmp si,4000h-3
    jb .l
.t: mov al,[si]
    mov [es:si],al
    inc si
    cmp si,4000h
    jb .t
    pop es
    pop ds
    ret

; DX = code byte mismatches (0-1FFFh), CX = attribute mismatches (even 2000h-3FFEh),
; BP = offset of the first mismatch (FFFFh if none)
verify:
    push ds
    push es
    mov ax,WS
    mov ds,ax
    mov ax,0A000h
    mov es,ax
    xor dx,dx
    mov bp,0FFFFh
    xor si,si
.c: mov al,[es:si]
    cmp al,[si]
    je .c1
    inc dx
    cmp bp,0FFFFh
    jne .c1
    mov bp,si
.c1:
    inc si
    cmp si,2000h
    jb .c
    xor cx,cx
.a: mov al,[es:si]
    cmp al,[si]
    je .a1
    inc cx
    cmp bp,0FFFFh
    jne .a1
    mov bp,si
.a1:
    add si,2
    cmp si,3FE0h                ; A3FE0h-A3FFFh: memory switches (write-protected)
    jb .a
    pop es
    pop ds
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

methods dw m_stosb, n_stosb, m_stosw, n_stosw, m_stosd, n_stosd
        dw m_movsb, n_movsb, m_movsw, n_movsw, m_movsd, n_movsd, m_oddd, n_oddd, 0
n_stosb db 'TVRAMW STOSB  codes $'
n_stosw db 'TVRAMW STOSW  codes $'
n_stosd db 'TVRAMW STOSD  codes $'
n_movsb db 'TVRAMW MOVSB  codes $'
n_movsw db 'TVRAMW MOVSW  codes $'
n_movsd db 'TVRAMW MOVSD  codes $'
n_oddd  db 'TVRAMW odd DW codes $'
msg_attr db '  attrs $'
msg_first db '  first $'
msg_hi  db 'TVRAMW attr words (want 5AA5 C33C): $'
hw0     dw 0
hw1     dw 0
results times 7*3 dw 0
crlf    db 13,10,'$'
