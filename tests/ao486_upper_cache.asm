; SPDX-License-Identifier: GPL-3.0-or-later
bits 16
org 0x1000
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x9000
    mov ax, 0x9000
    mov es, ax
    mov word [es:0], 0x11b8        ; mov ax,1111 / retf
    mov word [es:2], 0xcb11
    mov si, kernel
    mov di, 0x100
    mov cx, kernel_end-kernel
    rep movsb
    call 0x9000:0
    cmp ax, 0x1111
    jne fail
    call 0x9000:0
    cmp ax, 0x1111
    jne fail

    ; Ordinary CPU stores must snoop the native cached instruction address.
    mov word [es:1], 0x2222
    call 0x9000:0
    cmp ax, 0x2222
    jne fail

    ; Warm AFTER the mapping change, so that only the alias store can flush it.
    mov dx, 0x0463
    mov al, 8
    out dx, al
    call 0x9000:0
    cmp ax, 0x2222
    jne fail
    mov ax, 0xb000
    mov es, ax
    mov word [es:1], 0x3333
    call 0x9000:0
    cmp ax, 0x3333
    jne fail

    mov dx, 0x7ff2
    out dx, ax                    ; host DMA replaces the warmed native routine
    call 0x9000:0
    cmp ax, 0x4444
    jne fail

    mov dx, 0x0461
    xor al, al
    out dx, al                    ; 90000 now aliases 10000: bypass upper cache
    call 0x9000:0
    cmp ax, 0xaaaa
    jne fail
    mov ax, 0x1000
    mov es, ax
    mov word [es:1], 0xbbbb
    call 0x9000:0
    cmp ax, 0xbbbb
    jne fail
    ; Native upper RAM is currently uncacheable. A bank-AB store here must
    ; not resurrect a stale tag when the bank-89 native mapping is restored.
    mov ax, 0xb000
    mov es, ax
    mov word [es:1], 0x7777
    mov al, 9                     ; bit 0 is ignored by the real memory map
    out dx, al
    call 0x9000:0
    cmp ax, 0x7777
    jne fail

    call 0xe000:0                 ; ROM/peripherals must remain uncached
    cmp ax, 0x5555
    jne fail
    mov dx, 0x7ff4
    out dx, ax
    call 0xe000:0
    cmp ax, 0x6666
    jne fail

    mov dx, 0x7ff0
    mov ax, 0x0101
    out dx, ax
    call 0x9000:0x100
    cmp bx, 768
    jne fail
    cmp si, 256
    jne fail
    mov ax, 0x0201
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
kernel:
    mov cx, 256
    xor bx, bx
    xor si, si
.loop:
    add bx, 3
    inc si
    dec cx
    jnz .loop
    retf
kernel_end:
