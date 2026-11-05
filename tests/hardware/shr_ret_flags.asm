; VMM's semaphore wait check (c0008c38): mov ax,[esi] / dec eax / shr ah,7 /
; ret, and the caller's jne right after the return. The shift's ZF must reach
; the jne across the RET. Each case leaves 1 (correct) or 0 in a register:
; EBX = near call, ECX = indirect call through the stack, EDI = with SF preset.
        bits 16
        org 1000h
        cli
        xor ax, ax
        mov ds, ax
        mov ss, ax
        mov sp, 0f00h
        mov word [500h], 1
        mov esi, 500h
        xor ebx, ebx
        xor ecx, ecx
        xor edi, edi
        ; case 1: near call
        mov eax, 0c0fce300h
        call chk
        jne .c1bad
        mov ebx, 1
.c1bad:
        ; case 2: indirect call through the stack, like call [esp+8]
        push word chk
        mov bp, sp
        mov eax, 0c0fce300h
        call word [bp]
        jne .c2bad
        mov ecx, 1
.c2bad:
        add sp, 2
        ; case 3: SF/ZF=0 flags before (as in VMM: 3086h)
        mov eax, 80000000h
        add eax, 1                      ; SF=1, ZF=0
        mov eax, 0c0fce300h
        call chk
        jne .c3bad
        mov edi, 1
.c3bad:
        mov dx, 7fe4h
        out dx, al
        mov dx, 7ff0h
        mov ax, 600dh
        out dx, ax
        hlt
chk:
        mov ax, [si]
        dec eax
        shr ah, 7
        ret
