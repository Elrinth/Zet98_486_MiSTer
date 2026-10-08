; SPDX-License-Identifier: GPL-3.0-or-later
; DOS .COM probe; assemble with nasm -f bin -o ROMBANK.COM.
; Does not write D800 RAM or change the selected bank permanently.
bits 16
org 100h
    pushf
    cli
    mov dx,063ch
    in al,dx
    mov bl,al
    and al,0fch
    or al,2
    out dx,al
    mov ax,0d800h
    mov es,ax
    mov si,[es:000ch]
    mov al,bl
    and al,0fch
    or al,1
    out dx,al
    mov bh,al
    in al,dx
    cmp al,bh
    jne failed
    cmp word [es:000ch],0ffcbh
    jne failed
    cmp word [es:000eh],0ffffh
    jne failed
    call 0d800h:000ch
    mov al,bl
    and al,0fch
    or al,2
    out dx,al
    cmp [es:000ch],si
    jne failed
    mov si,pass_text
    xor cx,cx
    jmp restore
failed:
    mov si,fail_text
    mov cx,1
restore:
    mov al,bl
    out dx,al
    popf
    mov dx,si
    mov ah,9
    int 21h
    mov ax,4c00h
    or al,cl
    int 21h
pass_text: db 'PASS: PC-9821 firmware bank, POST return, resident RAM preserved',13,10,'$'
fail_text: db 'FAIL: PC-9821 firmware bank',13,10,'$'
