; SPDX-License-Identifier: GPL-3.0-or-later
; CONVTEST.COM: conventional-memory coherence stress in real mode (for the
; main-RAM line buffer): mixed byte/word stores and reads inside 8-byte
; groups, overlapping REP MOVS both ways, RMW, and code written then run.
; Uses a 32 KB buffer after the program. Prints per-test error counts.
bits 16
cpu 486
org 100h
ROUNDS equ 300
BUF    equ 8000h                ; CS-relative 32 KB work buffer
REF    equ 4000h                ; 8 KB reference copy (kept in parallel)
    cld
    xor bp,bp
.round:
    ; T0: word fill, then single-byte stores at every offset, then word reads
    mov di,BUF
    mov cx,1000h
    mov ax,bp
.f0: stosw
    add ax,1357h
    loop .f0
    mov si,BUF
    mov cx,2000h
    mov dl,byte [ref_seed]
.b0: mov al,dl
    xor al,cl
    mov [si],al                 ; byte store
    mov bx,[si]                 ; word read covering the stored byte
    cmp bl,al
    je .b0n
    inc word [err+0]
.b0n: add si,1
    add dl,bl
    loop .b0
    ; T1: store a word, then read the other three words of its 8-byte group
    mov si,BUF
    mov cx,800h
.t1: mov ax,si
    xor ax,bp
    mov [si+2],ax
    mov bx,[si]
    mov dx,[si+4]
    mov di,[si+6]
    cmp ax,[si+2]
    je .t1a
    inc word [err+2]
.t1a: mov [si],bx               ; write back neighbours unchanged
    mov [si+4],dx
    mov [si+6],di
    add si,8
    loop .t1
    ; T2: overlapping forward copy (src < dst) by bytes, verify against REF
    mov si,BUF
    mov di,REF
    mov cx,1000h
.r2: mov ax,cx
    xor ax,bp
    mov [si],ax
    mov [di],ax
    add si,2
    add di,2
    loop .r2
    ; shift BUF up by 3 bytes using a backward copy (correct overlap order)
    std
    mov si,BUF+1FFFh
    mov di,BUF+2002h
    mov cx,2000h
    rep movsb
    cld
    mov si,REF
    mov di,BUF+3
    mov cx,2000h
    repe cmpsb
    je .t2ok
    inc word [err+4]
.t2ok:
    ; T3: overlapping copy down by 5 bytes with REP MOVSW (forward is safe)
    mov si,BUF+5
    mov di,BUF
    mov cx,0F00h
    rep movsw
    mov si,BUF
    mov di,REF
    mov cx,1E00h
    ; BUF[k] should equal REF[k+2] (shift up 3 then down 5 = down 2)
    add di,2
    repe cmpsb
    je .t3ok
    inc word [err+6]
.t3ok:
    ; T4: RMW chains on words and bytes, checked with a register copy
    mov si,BUF
    mov cx,800h
    xor dx,dx
.t4: mov word [si],0
    add word [si],cx
    xor byte [si+1],5Ah
    inc word [si]
    mov ax,cx
    xor ah,5Ah
    inc ax
    mov bx,[si]
    cmp bx,ax
    je .t4n
    inc word [err+8]
    cmp word [f_si],0
    jne .t4n
    mov [f_exp],ax              ; first failure: expected, read, re-read, offset
    mov [f_got],bx
    mov bx,[si]
    mov [f_again],bx
    mov [f_si],si
    mov [f_round],bp
.t4n: add si,6
    loop .t4
    ; T5: write a small routine into the buffer and call it (code fetch
    ; after data stores to the same group)
    mov di,BUF+100h
    add di,bp
    and di,0FFF0h
    or di,8000h
    mov [code_at],di
    mov al,0B8h                 ; mov ax,imm16
    stosb
    mov ax,bp
    xor ax,0A55Ah
    stosw
    mov al,0C3h                 ; ret
    stosb
    call word [code_at]
    mov dx,bp
    xor dx,0A55Ah
    cmp ax,dx
    je .t5ok
    inc word [err+10]
.t5ok:
    add byte [ref_seed],7
    inc bp
    cmp bp,ROUNDS
    jb .round
    ; report
    mov si,err
    mov cx,6
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
    mov si,f_exp
    mov cx,5
.f: push cx
    mov ax,[si]
    call hex16
    mov dl,' '
    mov ah,2
    int 21h
    add si,2
    pop cx
    loop .f
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
ref_seed db 3
code_at  dw 0
err      times 6 dw 0
f_exp    dw 0
f_got    dw 0
f_again  dw 0
f_si     dw 0
f_round  dw 0
crlf     db 13,10,'$'
