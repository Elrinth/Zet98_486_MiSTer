    ; Synthetic ROM checksum. Exercise uncached LODSW, separate low/high
    ; byte sums, LOOP and flags surviving an indirect jump to the decision.
    ; The testbench seeds 512 words at F800:0000 with a zero lane checksum.
    mov word [0x27f0], 13
    mov ax, 0xf800
    mov es, ax
    xor si, si
    xor dx, dx
    mov cx, 512
    mov bp, z486_checksum_zero
z486_checksum_loop:
    es lodsw
    add dl, al
    add dh, ah
    loop z486_checksum_loop
    or dx, dx
    jmp bp
z486_checksum_zero:
    jnz fail
    cmp si, 1024
    jne fail

    ; A nonzero starting sum must reach the opposite branch without a
    ; stale zero flag from the preceding checksum or the last LOOP.
    mov word [0x27f0], 14
    xor si, si
    mov dx, 1
    mov cx, 512
    mov bp, z486_checksum_nonzero
    jmp z486_checksum_loop
z486_checksum_nonzero:
    jz fail
    cmp dx, 1
    jne fail
    xor ax, ax
    mov es, ax
    mov word [0x27f0], 0
