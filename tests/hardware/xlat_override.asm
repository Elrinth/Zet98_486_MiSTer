; SPDX-License-Identifier: GPL-3.0-or-later
; XLAT with segment overrides. The PC-98 BIOS keyboard handler builds the
; key-state bitmap mask with CS: XLATB while DS=0 (F000:E683); if the override
; is ignored, the BIOS key bitmap at 0000:052A never changes (Mime's menus).
; Loaded at 1000:0100. Reports 600Dh to port 7FF0h on success; on failure
; EBP holds the failure code and 0BADh goes to port 7FE4h.
        cpu     486
        org     100h

bits 16
start:  cli
        cld
        mov     ax, cs
        mov     ss, ax
        mov     sp, 0FFF0h
        ; decoy table at 2000:0200 (DS), real table at CS:table
        mov     ax, 2000h
        mov     ds, ax
        mov     es, ax
        mov     di, 0200h
        mov     cx, 8
        mov     al, 0EEh
        rep     stosb
        xor     ax, ax
        mov     fs, ax
        mov     gs, ax

        ; plain XLATB uses DS
        mov     bx, 0200h
        mov     al, 3
        xlatb
        cmp     al, 0EEh
        mov     ebp, 1
        jne     fail

        ; CS: XLATB (the BIOS form), with and without a warm cache
        mov     cx, 8
        xor     dx, dx
.cs:    mov     bx, table
        mov     al, dl
        cs xlatb
        mov     si, dx
        cmp     al, [cs:table+si]
        mov     ebp, 2
        jne     fail
        inc     dx
        loop    .cs

        ; ES: and SS: overrides
        mov     ax, 2000h
        mov     es, ax
        mov     bx, 0200h
        mov     al, 5
        es xlatb
        cmp     al, 0EEh
        mov     ebp, 3
        jne     fail
        push    ds
        mov     ax, cs
        mov     ds, ax
        mov     bx, table
        mov     ax, 2000h
        mov     ds, ax              ; DS = decoy, SS = CS holds the table
        mov     al, 6
        ss xlatb
        pop     ds
        cmp     al, 40h
        mov     ebp, 4
        jne     fail

        ; the exact BIOS sequence: DS=0, CS: XLATB, XOR into [BX+52Ah]
        xor     ax, ax
        mov     ds, ax
        mov     byte [052Dh], 0
        mov     al, 1Ch             ; Return make code
        mov     cl, al
        and     al, 7
        mov     bx, table
        cs xlatb
        xor     bx, bx
        mov     bl, cl
        shr     bx, 3
        xor     [bx+052Ah], al
        cmp     byte [052Dh], 10h
        mov     ebp, 5
        jne     fail

        mov     dx, 7FF0h
        mov     ax, 600Dh
        out     dx, ax
        hlt
        jmp     $

fail:   mov     dx, 7FE4h
        mov     ax, 0BADh
        out     dx, ax
        hlt
        jmp     $

table:  db      01h, 02h, 04h, 08h, 10h, 20h, 40h, 80h
