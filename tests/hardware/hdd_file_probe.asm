; SPDX-License-Identifier: GPL-3.0-or-later
; DOS file-level persistence test for a disposable writable game-image copy.
; Refuse an existing filename; keep the result for independent host checking.
bits 16
cpu 386
org 100h
start:
    push cs
    pop ds
    push cs
    pop es
    cld
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,name
    mov ax,5b00h             ; create NEW file; never truncate an existing one
    xor cx,cx
    int 21h
    jc failed
    mov [handle],ax
    mov word [block],0
.write:
    mov di,buffer
    mov cx,1024
    mov ax,[block]
.pattern:
    stosb
    add al,37
    loop .pattern
    mov bx,[handle]
    mov dx,buffer
    mov cx,1024
    cmp word [block],68
    jne .length
    mov cx,369              ; total 70,001 bytes, across several FAT clusters
.length:
    mov [amount],cx
    mov ah,40h
    int 21h
    jc close_failed
    cmp ax,[amount]
    jne close_failed
    inc word [block]
    cmp word [block],69
    jb .write
    mov bx,[handle]
    mov ah,3eh
    int 21h
    jc failed
    mov ah,0dh
    int 21h
    mov dx,name
    mov ax,3d00h
    int 21h
    jc failed
    mov [handle],ax
    mov word [block],0
.read:
    mov bx,[handle]
    mov dx,buffer
    mov cx,1024
    mov ah,3fh
    int 21h
    jc close_failed
    mov cx,1024
    cmp word [block],68
    jne .read_length
    mov cx,369
.read_length:
    cmp ax,cx
    jne close_failed
    mov si,buffer
    mov ax,[block]
.check:
    cmp [si],al
    jne close_failed
    inc si
    add al,37
    loop .check
    inc word [block]
    cmp word [block],69
    jb .read
    mov bx,[handle]
    mov dx,buffer
    mov cx,1
    mov ah,3fh
    int 21h
    jc close_failed
    test ax,ax
    jnz close_failed
    mov bx,[handle]
    mov ah,3eh
    int 21h
    jc failed
    mov ah,0dh
    int 21h
    mov dx,pass_text
    mov ah,9
    int 21h
    jmp halt
close_failed:
    mov bx,[handle]
    mov ah,3eh
    int 21h
failed:
    mov dx,fail_text
    mov ah,9
    int 21h
halt:
    sti
    hlt
    jmp halt
critical_error:
    mov al,3
    iret
handle: dw 0
amount: dw 0
block: dw 0
name: db 'A:\Z98WRITE.BIN',0
pass_text: db 13,10,'PASS: 70001-byte HDD file created, flushed, reopened,',13,10
    db 'verified byte-for-byte and EOF checked.',13,10,'Leave this screen for host verification.',13,10,'$'
fail_text: db 13,10,'FAIL: HDD file test (existing Z98WRITE.BIN also refuses).',13,10,'$'
buffer equ 2000h
times 0 * (1 / (($ - $$) < 1f00h)) db 0
