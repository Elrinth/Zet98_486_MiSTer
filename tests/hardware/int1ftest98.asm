; SPDX-License-Identifier: GPL-3.0-or-later
; INT1F.COM: PC-98 INT 1Fh AH=90h block moves (as NEC HIMEM uses them):
; conventional -> extended -> conventional at moving offsets, verified.
; Prints rounds, mismatches, CF failures and the first bad round.
bits 16
cpu 486
org 100h
ROUNDS equ 3000
    ; source pattern
    mov di,srcbuf
    mov cx,4000h/2
    xor ax,ax
.i: stosw
    add ax,7F4Bh
    loop .i
    xor ebp,ebp
.r:
    ; extended target: 2 MB + round*4100, moving and unaligned
    mov eax,ebp
    imul eax,eax,4100
    and eax,7FFFFh
    add eax,200001h
    mov [ext],eax
    ; descriptors: source = our segment, destination = extended
    mov ax,cs
    movzx eax,ax
    shl eax,4
    mov [lin],eax
    ; move 1: srcbuf -> ext
    mov eax,[lin]
    add eax,srcbuf
    call set_src
    mov eax,[ext]
    call set_dst
    mov cx,4000h
    xor si,si
    xor di,di
    call move
    jc .cf
    ; move 2: ext -> dstbuf
    mov eax,[ext]
    call set_src
    mov eax,[lin]
    add eax,dstbuf
    call set_dst
    mov cx,4000h
    xor si,si
    xor di,di
    call move
    jc .cf
    ; verify
    push es
    push ds
    pop es
    mov si,srcbuf
    mov di,dstbuf
    mov cx,4000h/4
    cld
    repe cmpsd
    pop es
    je .ok
    inc dword [bad]
    cmp dword [first],0
    jne .ok
    mov [first],ebp
    inc dword [first]
    jmp .ok
.cf: inc dword [cfail]
.ok:
    ; clear destination, perturb source
    mov di,dstbuf
    mov cx,4000h/4
    xor eax,eax
    push es
    push ds
    pop es
    rep stosd
    pop es
    mov si,srcbuf
    mov cx,4000h/4
.pt: add [si],ebp
    add si,4
    loop .pt
    inc ebp
    cmp ebp,ROUNDS
    jb .r
    mov eax,ebp
    call hex32
    mov eax,[bad]
    call hex32
    mov eax,[cfail]
    call hex32
    mov eax,[first]
    call hex32
    mov dx,crlf
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h

set_src:                        ; EAX = linear base
    mov [gdt+10h+2],ax
    shr eax,16
    mov [gdt+10h+4],al
    mov word [gdt+10h],0ffffh
    mov byte [gdt+10h+5],93h
    ret
set_dst:
    mov [gdt+18h+2],ax
    shr eax,16
    mov [gdt+18h+4],al
    mov word [gdt+18h],0ffffh
    mov byte [gdt+18h+5],93h
    ret
move:
    push es
    push ds
    pop es
    mov bx,gdt
    mov ah,90h
    int 1fh
    pop es
    ret
hex32:
    mov cx,8
.h: rol eax,4
    push eax
    and al,0fh
    add al,'0'
    cmp al,'9'
    jbe .q
    add al,7
.q: mov dl,al
    mov ah,2
    int 21h
    pop eax
    loop .h
    mov dl,' '
    mov ah,2
    int 21h
    ret
lin   dd 0
ext   dd 0
bad   dd 0
cfail dd 0
first dd 0
crlf  db 13,10,'$'
align 8
gdt   times 30h db 0
align 16
srcbuf times 4000h db 0
dstbuf times 4000h db 0
