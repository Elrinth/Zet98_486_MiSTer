; SPDX-License-Identifier: GPL-3.0-or-later
; Interrupt service under the z486 execution-rate throttle. Long REP MOVSW
; and REP STOSW blocks run with the testbench timer IRQ (vector 08h, every
; 10000 clocks, PIT_PM_TEST=1) unmasked. Each REP pays its execution debt
; after it retires; a pending interrupt must still be taken promptly, so the
; script compares accepted IRQs with the elapsed time. The copied data is
; verified. Loaded at 1000:0100 (DOS_PROBE=1).
; Success: 600Dh to port 7FF0h. Failure: EBP=stage, 0BADh to port 7FF0h.
        cpu     486
        org     100h
bits 16

%ifndef BLOCKS
%define BLOCKS 6
%endif
WORDS   equ     16384

start:  cli
        cld
        mov     ax, cs
        mov     ss, ax
        mov     sp, 0FFF0h
        xor     ax, ax
        mov     ds, ax
        mov     word [08h*4], irq0
        mov     [08h*4+2], cs
        mov     word [cs:ticks], 0
        ; source pattern in 4000:0000
        mov     ax, 4000h
        mov     es, ax
        xor     di, di
        mov     cx, WORDS
        mov     ax, 5A5Ah
.fill:  stosw
        add     ax, 3
        loop    .fill
        mov     al, 0FEh                ; unmask IRQ0 only
        out     02h, al
        sti
        mov     bp, BLOCKS
.block: mov     ax, 4000h
        mov     ds, ax
        mov     ax, 5000h
        mov     es, ax
        xor     si, si
        xor     di, di
        mov     cx, WORDS
        rep     movsw
        dec     bp
        jnz     .block
        cli
        mov     al, 0FFh
        out     02h, al
        ; verify the last copy
        mov     ax, 5000h
        mov     ds, ax
        xor     si, si
        mov     cx, WORDS
        mov     dx, 5A5Ah
        mov     ebp, 1
.check: lodsw
        cmp     ax, dx
        jne     fail
        add     dx, 3
        loop    .check
        mov     ebp, 2
        cmp     word [cs:ticks], 3
        jb      fail
        mov     dx, 7FF0h
        mov     ax, 600Dh
        out     dx, ax
        hlt
        jmp     $

irq0:   inc     word [cs:ticks]
        push    ax
        mov     al, 20h
        out     00h, al
        pop     ax
        iret

fail:   mov     dx, 7FF0h
        mov     ax, 0BADh
        out     dx, ax
        hlt
        jmp     $

ticks:  dw      0
