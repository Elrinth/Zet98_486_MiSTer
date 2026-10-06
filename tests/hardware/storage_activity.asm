; SPDX-License-Identifier: GPL-3.0-or-later
; ACTIVITY.COM 0..6: D0 read, D1 read, D0 write, D1 write, CD read,
; HDD file read, HDD file write. ONLY use disposable activity test images:
; floppy reads expect 5Ah; writes replace sectors C0/1 H0 R1 with A5h.
; ACTTEST.DAT must be 16 KiB of A5h; raw ISO sectors must contain 3Ch.
bits 16
cpu 386
org 100h
    cld
    push cs
    pop ds
    push cs
    pop es
    cmp byte [80h],2
    jb usage
    mov al,[82h]
    sub al,'0'
    cmp al,6
    ja usage
    mov [mode],al
    add al,'0'
    mov [mode_text],al
    mov dx,title
    call puts
    mov di,buffer
    mov ax,0a5a5h
    mov cx,8192
    rep stosw
    mov word [passes],256
    cmp byte [mode],4
    je cd_test
    ja file_test
    mov word [passes],64
    mov al,[mode]
    and al,1
    or al,90h
    mov [drive],al
    mov ah,3
    int 1bh
    jc failure
    mov al,[drive]
    mov ah,7
    int 1bh
    jc failure
floppy_loop:
    mov ah,56h
    cmp byte [mode],2
    jb .read
    mov ah,55h
.read:
    call floppy_sector
    jc failure
    cmp byte [mode],2
    jb .verify
    mov ah,56h
    call floppy_sector
    jc failure
.verify:
    mov ax,5a5ah
    cmp byte [mode],2
    jb .expected
    mov ax,0a5a5h
.expected:
    mov di,buffer
    mov cx,512
    repe scasw
    jne failure
    dec word [passes]
    jnz floppy_loop
    jmp success
floppy_sector:
    mov al,[drive]
    mov bx,1024
    mov ch,3
    mov cl,[passes]
    and cl,1
    mov dx,1
    mov bp,buffer
    int 1bh
    ret
file_test:
    mov dx,filename
    mov ax,3d02h
    int 21h
    jc failure
    mov [handle],ax
.loop:
    mov bx,[handle]
    mov ax,4200h
    xor cx,cx
    xor dx,dx
    int 21h
    jc failure
    mov dx,buffer
    mov cx,16384
    mov ah,3fh
    cmp byte [mode],5
    je .transfer
    mov ah,40h
.transfer:
    int 21h
    jc failure
    cmp ax,16384
    jne failure
    mov di,buffer
    mov ax,0a5a5h
    mov cx,8192
    repe scasw
    jne failure
    dec word [passes]
    jnz .loop
    mov bx,[handle]
    mov ah,3eh
    int 21h
    jc failure
    jmp success
cd_test:
    mov dx,0432h
    mov al,1
    out dx,al
    mov dx,074ch
    mov al,2
    out dx,al
    mov si,tur
    call packet                 ; clear a possible mount unit-attention
    mov dx,064eh
    in al,dx
    mov word [passes],1024
.loop:
    mov si,read_cd
    call packet
    jc failure
    call wait_drq
    jc failure
    mov dx,0640h
    mov di,buffer
    mov cx,1024
    rep insw
    mov di,buffer
    mov ax,3c3ch
    mov cx,1024
    repe scasw
    jne failure
    call wait_idle
    jc failure
    dec word [passes]
    jnz .loop
    jmp success
packet:
    call wait_idle
    ; Previous command ERR is allowed; a new PACKET clears it.
    mov dx,064ch
    mov al,0a0h
    out dx,al
    mov dx,0648h
    xor al,al
    out dx,al
    add dx,2
    mov al,8
    out dx,al
    mov dx,064eh
    mov al,0a0h
    out dx,al
    call wait_drq
    jc .done
    mov dx,0640h
    mov cx,6
.word:
    lodsw
    out dx,ax
    loop .word
    clc
.done:
    ret
wait_drq:
    mov ecx,1000000
    mov dx,064eh
.poll:
    in al,dx
    test al,80h
    jnz .again
    test al,1
    jnz .fail
    test al,8
    jnz .ready
.again:
    dec ecx
    jnz .poll
.fail:
    stc
    ret
.ready:
    clc
    ret
wait_idle:
    mov ecx,1000000
    mov dx,064eh
.poll:
    in al,dx
    test al,88h
    jz .ready
    dec ecx
    jnz .poll
    stc
    ret
.ready:
    test al,1
    jnz .fail
    clc
    ret
.fail:
    stc
    ret
success:
    mov dx,pass_text
    jmp finish
failure:
    mov dx,fail_text
finish:
    push dx
    mov dx,0432h
    xor al,al
    out dx,al
    pop dx
    call puts
    mov ax,4c00h
    int 21h
usage:
    mov dx,usage_text
    jmp finish
puts:
    mov ah,9
    int 21h
    ret
mode db 0
drive db 90h
handle dw 0
passes dw 0
title db 13,10,'Activity mode '
mode_text db '0'
    db ': testing disposable media...',13,10,'$'
pass_text db 'PASS activity transfers',13,10,'$'
fail_text db 'FAIL activity transfer/data',13,10,'$'
usage_text db 'ACTIVITY 0..6 (disposable activity media only)',13,10,'$'
filename db 'ACTTEST.DAT',0
tur times 12 db 0
read_cd db 28h,0,0,0,0,16,0,0,1,0,0,0
buffer times 16384 db 0
