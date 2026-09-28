; SPDX-License-Identifier: GPL-3.0-or-later
; Steam Heart's (ST1.EXE) stack-pointer drift: the exact bytes of its
; 25E3:1540-158B sequence (two PUSH-argument / CALL FAR 1EFE:0008 / ADD SP,0Ch
; rounds) and of the called routine 1EFE:0008-0069, run with SS=DS=3000h for
; SP values 5000h-53FEh. On the MiSTer SP ended 6 bytes high after the first
; round and the later RETF jumped to 0058:0E62. Generated from the game by
; hand; the far-call segment is relocated to 1100h.
; Loaded at 1000:0100. Reports 600Dh to port 7FF0h on success; on failure
; EBP holds the failing SP and 0BADh goes to port 7FE4h.
        cpu     486
        org     100h
bits 16
start:  cli
        cld
        mov     ax, 3000h
        mov     ds, ax
        mov     ss, ax
        mov     cx, 200h                ; SP 5000h..53FEh
        mov     di, 5000h
.loop:  mov     sp, di
        mov     bp, sp
        mov     word [bp+6], 1          ; caller argument [bp+6]
        mov     si, 36h
        mov     word [si+7306h], 0E62h
        mov     word [si+7304h], 5
        mov     word [0A960h], 0        ; sprite count
        push    cx
        push    di
        mov     bp, sp
        sub     bp, 0                   ; BP = SP as in the game frame
        db 0C7h, 084h, 02Ch, 073h, 005h, 000h, 0FFh, 076h, 006h, 0B8h, 00Ah, 000h, 050h, 02Bh, 0C0h, 050h
        db 050h, 0FFh, 0B4h, 006h, 073h, 08Bh, 084h, 004h, 073h, 0B1h, 003h, 0D3h, 0E0h, 005h, 030h, 000h
        db 050h, 09Ah, 008h, 000h, 000h, 011h, 083h, 0C4h, 00Ch, 0FFh, 076h, 006h, 0B8h, 00Ah, 000h, 050h
        db 02Bh, 0C0h, 050h, 050h, 0FFh, 0B4h, 006h, 073h, 08Bh, 084h, 004h, 073h, 0B1h, 003h, 0D3h, 0E0h
        db 02Dh, 030h, 000h, 050h, 09Ah, 008h, 000h, 000h, 011h, 083h, 0C4h, 00Ch
        pop     di
        pop     cx
        cmp     sp, di
        jne     .bad
        add     di, 2
        loop    .loop
        mov     dx, 7FF0h
        mov     ax, 600Dh
        out     dx, ax
        hlt
        jmp     $
.bad:   movzx   ebp, di
        mov     dx, 7FE4h
        mov     ax, 0BADh
        out     dx, ax
        hlt
        jmp     $
        times   1008h - 100h - ($ - $$) db 90h
; 1100:0008 - the called routine, bytes as in the game
        db 055h, 08Bh, 0ECh, 056h, 081h, 03Eh, 060h, 0A9h, 000h, 002h, 07Dh, 053h, 0A1h, 060h, 0A9h, 08Bh
        db 0C8h, 0D1h, 0E0h, 003h, 0C1h, 0D1h, 0E0h, 003h, 0C1h, 0D1h, 0E0h, 08Bh, 0F0h, 08Bh, 046h, 006h
        db 089h, 084h, 07Eh, 074h, 08Bh, 046h, 008h, 089h, 084h, 080h, 074h, 08Bh, 046h, 00Ah, 089h, 084h
        db 082h, 074h, 08Bh, 046h, 00Ch, 089h, 084h, 084h, 074h, 08Ah, 046h, 00Eh, 088h, 084h, 086h, 074h
        db 0C6h, 084h, 087h, 074h, 000h, 08Ah, 046h, 010h, 088h, 084h, 088h, 074h, 0C6h, 084h, 089h, 074h
        db 000h, 0C6h, 084h, 08Ah, 074h, 000h, 0C6h, 084h, 08Bh, 074h, 000h, 0FFh, 006h, 060h, 0A9h, 05Eh
        db 05Dh, 0CBh
