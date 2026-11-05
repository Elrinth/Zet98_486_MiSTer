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
        xor edi, edi
        xor ebp, ebp
        ; v1: indirect call, flags captured inside the callee right after shr
        push word chk_push
        mov bp, sp
        mov eax, 0c0fce300h
        call word [bp]
        add sp, 2
        ; v2: indirect call, callee = shr ah,7 / ret with AH = 0 already
        push word chk_shr
        mov bp, sp
        mov eax, 0c0fc0000h
        call word [bp]
        jne .v2bad
        mov edi, 1
.v2bad:
        add sp, 2
        ; v3: indirect call to a bare RET, then the check inline
        push word bare_ret
        mov bp, sp
        call word [bp]
        add sp, 2
        mov eax, 0c0fce300h
        mov ax, [si]
        dec eax
        shr ah, 7
        jne .v3bad
        mov ebp, 1
.v3bad:
        mov dx, 7fe4h
        out dx, al
        mov dx, 7ff0h
        mov ax, 600dh
        out dx, ax
        hlt
chk_push:
        mov ax, [si]
        dec eax
        shr ah, 7
        pushfd
        pop ebx
        ret
chk_shr:
        shr ah, 7
        ret
bare_ret:
        ret
