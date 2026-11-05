; VMM's nested-exec completion check (c0008c38): mov ax,[esi] / dec eax /
; shr ah,7 / ret, then jne. ZF must come from the 8-bit AH result only.
; Reports through port 7FE4h (EBX = flags of the memory form, ESI = flags of
; register forms), then ends with 600Dh at 7FF0h.
        bits 16
        org 1000h
        cli
        xor ax, ax
        mov ds, ax
        mov ss, ax
        mov sp, 0f00h
        mov word [500h], 1
        mov eax, 0c0fce300h
        mov ax, [500h]
        dec eax                         ; c0fc0000: AH = 0
        shr ah, 7
        pushfd
        pop ebx
        mov ecx, eax
        mov eax, 0c0fc0000h
        shr ah, 7                       ; AH = 0 -> ZF = 1
        pushfd
        pop esi
        mov eax, 000080ffh
        shr ah, 7                       ; AH = 80h -> 1, ZF = 0
        pushfd
        pop edi
        mov dx, 7fe4h
        out dx, al
        mov dx, 7ff0h
        mov ax, 600dh
        out dx, ax
        hlt
