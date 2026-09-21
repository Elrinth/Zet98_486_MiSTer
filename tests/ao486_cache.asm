; SPDX-License-Identifier: GPL-3.0-or-later
bits 16
org 0x1000
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x9000
    mov dx, 0x7ff2
    call 0x2000
    cmp ax, 0x1111
    jne fail
    ; The test host updates a previously fetched routine while owning memory.
    out dx, ax
    call 0x2000
    cmp ax, 0x2222
    jne fail
    ; CPU self-modification must still use the normal write snoop.
    mov word [0x2001], 0x4444
    call 0x2000
    cmp ax, 0x4444
    jne fail
    call 0x8000:0
    cmp ax, 0x3333
    jne fail
    ; Banked/upper memory must fetch fresh code even without invalidation.
    mov dx, 0x7ff4
    out dx, ax
    call 0x8000:0
    cmp ax, 0x5555
    jne fail

    mov dx, 0x7ff0
    mov ax, 0x0101
    out dx, ax
    mov cx, 512
    xor bx, bx
    xor si, si
align 32, db 0x90
.alu:
    add bx, 3
    inc si
    dec cx
    jnz .alu
    cmp bx, 1536
    jne fail
    cmp si, 512
    jne fail
    mov ax, 0x0201
    out dx, ax

    mov ax, 0xa800
    mov es, ax
    xor di, di
    mov cx, 128
    mov ax, 0x0102
    out dx, ax
align 32, db 0x90
.vram:
    mov ax, [0x3000]
    stosw
    dec cx
    jnz .vram
    mov ax, 0x0202
    out dx, ax
    mov ax, 0x600d
    out dx, ax
    hlt
    jmp $
fail:
    mov dx, 0x7ff0
    mov ax, 0xdead
    out dx, ax
    hlt
    jmp $
