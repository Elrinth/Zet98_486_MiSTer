    ; Disk-style PIO: exactly 256 words through the real I/O bridge into an
    ; uncached upper-RAM buffer, then back out in order. With 16-bit address
    ; size, REP must use CX/SI/DI while preserving their nonzero high halves.
    mov word [0x27f0], 15
    mov dx, 0x7ff2
    mov ax, 1
    out dx, ax
    mov ax, 0xd800
    mov es, ax
    mov edi, 0xbeef0200
    mov ecx, 0x12340100
    mov dx, 0x0640
    cld
    rep insw
    cmp edi, 0xbeef0400
    jne fail
    cmp ecx, 0x12340000
    jne fail
    mov si, 0x0200
    xor bx, bx
    mov cx, 256
z486_pio_verify:
    mov ax, bx
    xor ax, 0xa500
    cmp [es:si], ax
    jne fail
    add si, 2
    inc bx
    loop z486_pio_verify

    mov dx, 0x7ff2
    mov ax, 2
    out dx, ax
    mov esi, 0xcafe0200
    mov ecx, 0x56780100
    mov dx, 0x0640
    es rep outsw
    cmp esi, 0xcafe0400
    jne fail
    cmp ecx, 0x56780000
    jne fail
    mov dx, 0x7ff2
    mov ax, 3
    out dx, ax
    xor ax, ax
    mov es, ax
