; SPDX-License-Identifier: GPL-3.0-or-later
; A20TEST.COM: HIMEM-style A20 gate checks in real mode, repeated. With A20
; off FFFF:xxxx must alias 0000:xxxx-10h; with A20 on it must be separate
; HMA RAM (100000h+). Counts mismatches per step and prints them.
bits 16
cpu 486
org 100h
ROUNDS equ 20000
    cli
    xor ax,ax
    mov fs,ax                   ; FS = 0000
    dec ax
    mov gs,ax                   ; GS = FFFF
    mov eax,[fs:80h]
    mov [save80],eax
    xor ebp,ebp                 ; round
.r:
    ; values for this round
    mov eax,ebp
    imul eax,eax,9E3779B1h
    mov ebx,eax
    not ebx
    ; 1: A20 off, write low, read through FFFF (must alias)
    mov al,3
    out 0f6h,al
    mov edx,ebp
    imul edx,edx,9E3779B1h      ; EDX = X (AL is used for the port writes)
    mov [fs:80h],edx
    cmp [gs:90h],edx
    je .s2
    inc dword [err1]
.s2:
    ; 2: A20 on, write HMA, low must keep X, HMA must read Y
    out 0f2h,al
    mov [gs:90h],ebx
    cmp [fs:80h],edx
    je .s2b
    inc dword [err2]
.s2b:
    cmp [gs:90h],ebx
    je .s3
    inc dword [err3]
.s3:
    ; 3: A20 off again: FFFF:90 aliases low (X)
    mov al,3
    out 0f6h,al
    cmp [gs:90h],edx
    je .s4
    inc dword [err4]
.s4:
    ; 4: A20 on: HMA still holds Y
    out 0f2h,al
    cmp [gs:90h],ebx
    je .s5
    inc dword [err5]
.s5:
    ; 5: HMA block write/read (real mode, A20 on): 64 dwords
    mov di,100h
    mov ecx,ebx
.w: mov [gs:di],ecx
    add ecx,ebp
    add di,4
    cmp di,200h
    jb .w
    mov di,100h
    mov ecx,ebx
.v: cmp [gs:di],ecx
    je .vn
    inc dword [err6]
.vn: add ecx,ebp
    add di,4
    cmp di,200h
    jb .v
    inc ebp
    cmp ebp,ROUNDS
    jb .r
    mov al,3
    out 0f6h,al
    mov eax,[save80]
    mov [fs:80h],eax
    sti
    mov si,err1
    mov cx,6
.p: push cx
    mov eax,[si]
    call hex32
    mov dl,' '
    mov ah,2
    int 21h
    add si,4
    pop cx
    loop .p
    mov dx,crlf
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
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
    ret
save80 dd 0
err1 dd 0
err2 dd 0
err3 dd 0
err4 dd 0
err5 dd 0
err6 dd 0
crlf db 13,10,'$'
