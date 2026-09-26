; SPDX-License-Identifier: GPL-3.0-or-later
; Architectural checks for the shift operand preread/timing path. Included in
; the PC-98 bridge smoke program; stage stays in RAM to identify a failure.
    mov word [0x27f0], 1
    mov eax, 0x12345681
    shl al, 1
    jnc fail
    jno fail
    cmp eax, 0x12345602
    jne fail

    mov word [0x27f0], 2
    mov eax, 0x12348001
    mov cl, 4
    sar ax, cl
    jc fail
    cmp eax, 0x1234f800
    jne fail
    mov eax, 0x80000001
    shr eax, 1
    jnc fail
    jno fail
    cmp eax, 0x40000000
    jne fail

    mov word [0x27f0], 3
    mov eax, 0x12348001
    rol ax, 1
    jnc fail
    jno fail
    cmp eax, 0x12340003
    jne fail
    mov eax, 0x12345603
    ror al, 1
    jnc fail
    jno fail
    cmp eax, 0x12345681
    jne fail

    mov word [0x27f0], 4
    mov al, 0x80
    stc
    rcl al, 1
    jnc fail
    jno fail
    cmp al, 1
    jne fail
    mov ax, 1
    stc
    rcr ax, 1
    jnc fail
    jno fail
    cmp ax, 0x8000
    jne fail

    ; Zero and masked-zero counts preserve both the destination and flags.
    mov word [0x27f0], 5
    mov eax, 0x91827364
    xor ecx, ecx
    stc
    shl eax, cl
    jnc fail
    jnz fail
    cmp eax, 0x91827364
    jne fail
    mov cl, 32
    stc
    shr eax, cl
    jnc fail
    jnz fail
    cmp eax, 0x91827364
    jne fail
    mov eax, 1
    mov cl, 31
    shl eax, cl
    jc fail
    cmp eax, 0x80000000
    jne fail
    sar eax, cl
    jc fail
    cmp eax, 0xffffffff
    jne fail

    mov word [0x27f0], 6
    mov eax, 0x12345678
    mov ebx, 0x9abcdef0
    shld eax, ebx, 4
    jnc fail
    cmp eax, 0x23456789
    jne fail
    mov eax, 0x12345678
    mov cl, 4
    shrd eax, ebx, cl
    jnc fail
    cmp eax, 0x01234567
    jne fail

    ; Memory operands also exercise the cache/fabric handoff after SHIFT2.
    mov word [0x27f0], 7
    mov word [0x2603], 0x1234
    mov dx, 0xabcd
    shld word [0x2603], dx, 4
    jnc fail
    cmp word [0x2603], 0x234a
    jne fail
    mov word [0x2603], 0x1234
    shrd word [0x2603], dx, 4
    jc fail
    cmp word [0x2603], 0xd123
    jne fail

    mov word [0x27f0], 8
    mov eax, 0x80000000
    bsr ebx, eax
    jz fail
    cmp ebx, 31
    jne fail
    mov eax, 0x00010000
    bsf ebx, eax
    jz fail
    cmp ebx, 16
    jne fail
    xor eax, eax
    bsr ebx, eax
    jnz fail

    ; Signed memory bit indices use the same preread path as ordinary shifts.
    mov word [0x27f0], 9
    mov word [0x2600], 0x8000
    mov word [0x2602], 0
    mov cx, -1
    bt word [0x2602], cx
    jnc fail
    btr word [0x2602], cx
    jnc fail
    cmp word [0x2600], 0
    jne fail
    bts word [0x2602], cx
    jc fail
    cmp word [0x2600], 0x8000
    jne fail
    btc word [0x2602], cx
    jnc fail
    cmp word [0x2600], 0
    jne fail

    mov word [0x27f0], 10
    mov dword [0x2620], 0x80000000
    mov dword [0x2628], 0
    mov ecx, -33
    bt dword [0x2628], ecx
    jnc fail
    btr dword [0x2628], ecx
    jnc fail
    cmp dword [0x2620], 0
    jne fail
    mov eax, 0x80000000
    mov ecx, -1
    bt eax, ecx
    jnc fail
    btr eax, ecx
    jnc fail
    test eax, eax
    jnz fail
    ; A load's immediate successor must see the newly loaded register,
    ; including high-byte/partial writes and a loaded signed bit index.
    mov word [0x27f0], 11
    mov dword [0x2640], 0x80018081
    mov eax, [0x2640]
    shr eax, 1
    jnc fail
    cmp eax, 0x4000c040
    jne fail
    mov eax, 0x12345678
    mov ah, [0x2640]
    shr ah, 1
    jnc fail
    cmp eax, 0x12344078
    jne fail
    mov ax, [0x2640]
    bt ax, 15
    jnc fail
    mov word [0x2644], -1
    mov cx, [0x2644]
    bt word [0x2642], cx
    jnc fail

    ; Consecutive shifts consume the previous instruction's deferred result.
    mov word [0x27f0], 12
    mov eax, 0x80000001
    rol eax, 1
    ror eax, 1
    shl eax, 1
    shr eax, 1
    cmp eax, 1
    jne fail
    mov word [0x27f0], 0
