; SPDX-License-Identifier: GPL-3.0-or-later
; RMWTEST.COM: narrow store -> read-modify-write sequences on conventional
; memory (main-RAM line buffer bisection). Each test walks a 24 KB buffer with
; a 6-byte stride (words at every alignment inside 8-byte groups), ROUNDS
; times, and counts results that differ from a register computation.
;  S1 store word, load word        S2 store 0, ADD word [m],CX
;  S3 store word, XOR byte [m+1]   S4 store word, INC word [m]
;  S5 ADD then INC (two RMWs)      S6 byte store [m+1], then ADD word [m]
;  S7 store 0, ADD, XOR byte, INC   S8 = S7 without INC
;  S9 = S7 without ADD              S10 store 0, ADD, INC, XOR byte
bits 16
cpu 486
org 100h
ROUNDS equ 600
BUF    equ 4000h
%macro s1 0
    mov ax,cx
    xor ax,bp
    mov [si],ax
    cmp [si],ax
    je %%ok
    inc word [err+0]
%%ok:
%endmacro
%macro s2 0
    mov word [si],0
    add word [si],cx
    cmp [si],cx
    je %%ok
    inc word [err+2]
%%ok:
%endmacro
%macro s3 0
    mov [si],cx
    xor byte [si+1],5Ah
    mov ax,cx
    xor ah,5Ah
    cmp [si],ax
    je %%ok
    inc word [err+4]
%%ok:
%endmacro
%macro s4 0
    mov [si],cx
    inc word [si]
    mov ax,cx
    inc ax
    cmp [si],ax
    je %%ok
    inc word [err+6]
%%ok:
%endmacro
%macro s5 0
    mov [si],bp
    add word [si],cx
    inc word [si]
    mov ax,bp
    add ax,cx
    inc ax
    cmp [si],ax
    je %%ok
    inc word [err+8]
%%ok:
%endmacro
%macro s6 0
    mov [si],bp
    mov byte [si+1],cl
    add word [si],cx
    mov ax,bp
    mov ah,cl
    add ax,cx
    cmp [si],ax
    je %%ok
    inc word [err+10]
%%ok:
%endmacro

%macro s7 0
    mov word [si],0
    add word [si],cx
    xor byte [si+1],5Ah
    inc word [si]
    mov ax,cx
    xor ah,5Ah
    inc ax
    cmp [si],ax
    je %%ok
    inc word [err+12]
%%ok:
%endmacro
%macro s8 0
    mov word [si],0
    add word [si],cx
    xor byte [si+1],5Ah
    mov ax,cx
    xor ah,5Ah
    cmp [si],ax
    je %%ok
    inc word [err+14]
%%ok:
%endmacro
%macro s9 0
    mov word [si],cx
    xor byte [si+1],5Ah
    inc word [si]
    mov ax,cx
    xor ah,5Ah
    inc ax
    cmp [si],ax
    je %%ok
    inc word [err+16]
%%ok:
%endmacro
%macro s10 0
    mov word [si],0
    add word [si],cx
    inc word [si]
    xor byte [si+1],5Ah
    mov ax,cx
    inc ax
    xor ah,5Ah
    cmp [si],ax
    je %%ok
    inc word [err+18]
%%ok:
%endmacro

    cld
    xor bp,bp
round:
%macro WALK 1
    mov si,BUF
    mov cx,1000h
%%l:
    %1
    add si,6
    loop %%l
%endmacro
    WALK s1
    WALK s2
    WALK s3
    WALK s4
    WALK s5
    WALK s6
    WALK s7
    WALK s8
    WALK s9
    WALK s10
    inc bp
    cmp bp,ROUNDS
    jb round
    mov si,err
    mov cx,10
.p: push cx
    mov ax,[si]
    call hex16
    mov dl,' '
    mov ah,2
    int 21h
    add si,2
    pop cx
    loop .p
    mov dx,crlf
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h

hex16:
    mov cx,4
.h: rol ax,4
    push ax
    and al,0fh
    add al,'0'
    cmp al,'9'
    jbe .q
    add al,7
.q: mov dl,al
    mov ah,2
    int 21h
    pop ax
    loop .h
    ret
err  times 10 dw 0
crlf db 13,10,'$'
