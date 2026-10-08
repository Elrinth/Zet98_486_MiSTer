; SPDX-License-Identifier: GPL-3.0-or-later
; Word store followed at once by a word load of the same stack slot, with a
; different value in the adjacent word, after a store through ES. This is the
; return sequence of Windows 95 Setup's SYSDETMG.DLL selector allocator
; (mov [bp-6] / mov word [es:bx+6],0 / mov word [bp-0Ah],0 / mov [bp-8],di /
; mov ax,[bp-0Ah] / mov dx,[bp-8]); the core returned the [bp-6] word in DX.
; Every BP alignment 0..3 and several store-queue fillings are checked.
; Loaded at 1000:0100 by z486_xms_resident_tb. Reports 600Dh to port 7FF0h;
; on failure EBP = case, EAX/EDX = values read, then 0BADh to port 7FE4h.
        cpu     486
        org     100h
bits 16
start:  cli
        cld
        mov     ax, cs
        mov     ds, ax
        mov     ss, ax
        mov     sp, 0F000h
        mov     ax, 2000h
        mov     es, ax
        xor     esi, esi                ; case counter
        mov     cx, 400                 ; rounds
.round: mov     bx, cx
        and     bx, 3
        mov     bp, 0E000h
        add     bp, bx                  ; alignment 0..3
        mov     di, cx
        xor     di, 235Fh
        mov     word [bp-6], 2367h      ; neighbour word
        mov     word [bp-8], 1111h
        mov     word [bp-0Ah], 2222h
        mov     word [bp-0Ch], 3333h
        mov     bx, cx
        and     bx, 0F8h
        ; --- SYSDETMG tail ---
        mov     word [es:bx+6], 0
        mov     word [bp-0Ah], 0
        mov     [bp-8], di
        mov     ax, [bp-0Ah]
        mov     dx, [bp-8]
        ; ---------------------
        inc     esi
        mov     ebp, esi
        cmp     ax, 0
        jne     fail
        cmp     dx, di
        jne     fail
        ; variant: dword neighbour read straight after the word store
        mov     bp, 0E000h
        mov     bx, cx
        and     bx, 3
        add     bp, bx
        mov     word [bp-6], 2367h
        mov     [bp-8], di
        mov     edx, [bp-8]
        inc     esi
        mov     ebp, esi
        cmp     dx, di
        jne     fail
        shr     edx, 16
        cmp     dx, 2367h
        jne     fail
        dec     cx
        jnz     .round
        mov     dx, 7FF0h
        mov     ax, 600Dh
        out     dx, ax
        hlt
        jmp     short $
fail:   mov     dx, 7FE4h
        push    ax
        mov     ax, 0BADh
        out     dx, ax
        pop     ax
        hlt
        jmp     short $
