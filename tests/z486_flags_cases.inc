; SPDX-License-Identifier: GPL-3.0-or-later
; Flag restoration and precise real-mode single-step entry/IRET. Same cases
; as the hardware flags probe, with a shorter loop for the CPU watchdog.
    mov word [4],flags_trap_handler
    mov word [6],0
    mov word [0x27e0],0       ; trap count
    mov byte [0x27e2],0       ; unexpected saved return IP
    mov word [0x27e4],0       ; intended return IP (none yet)
    xor si,si
    mov di,128
flags_roundtrip:
    mov ax,si
    and ax,0cd5h
    or ax,2
    push ax
    popf
    pushf
    pop dx
    xor dx,ax
    test dx,0cd5h
    jnz fail
    movzx eax,si
    shl eax,18
    and eax,40000h
    mov bx,si
    and bx,0cd5h
    or bx,2
    mov ax,bx
    push eax
    popfd
    pushfd
    pop edx
    xor edx,eax
    test edx,40cd5h
    jnz fail
    mov ax,si
    and ax,0ffh
    mov ah,al
    sahf
    lahf
    and al,0d5h
    or al,2
    cmp al,ah
    jne fail
    cmp word [0x27e0],0
    jne fail
    add si,37               ; exercise OF/DF as well as low flags in 128 samples
    dec di
    jnz flags_roundtrip
    mov word [0x27e4],flags_after_step
    push word 0102h
    popf
    nop
flags_after_step:
    cli
    cmp word [0x27e0],1
    jne fail
    cmp byte [0x27e2],0
    jne fail
    pushf
    pop ax
    test ax,0100h
    jnz fail
    push dword 2
    popfd
    cld
    jmp flags_done
flags_trap_handler:
    push bp
    mov bp,sp
    push ax
    inc word [0x27e0]
    mov ax,[ss:bp+2]
    cmp ax,[0x27e4]
    je .expected
    mov byte [0x27e2],1
.expected:
    and word [ss:bp+6],0feffh
    pop ax
    pop bp
    iret
flags_done:
