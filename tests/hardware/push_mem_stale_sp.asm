; SPDX-License-Identifier: GPL-3.0-or-later
; PUSH r/m16 after a run of pushes (Steam Heart's ST1.EXE 25E3:1569-1578):
;   PUSH [BP+6] / PUSH 0Ah / PUSH 0 / PUSH 0 / PUSH WORD [SI+7306h] / PUSH AX
; On the MiSTer the memory-operand push stored 6 bytes too high (the SP of
; three pushes earlier) when its operand read missed the cache, overwriting
; the PUSH 0Ah slot; the stack later unwound into 0058:0E62. Each round moves
; SI to a new line (first read of it) and the stack by a word, then checks
; every pushed word at its exact address.
; Loaded at 1000:0100. Reports 600Dh to port 7FF0h on success; on failure
; EBP = round, and 0BADh goes to port 7FE4h.
        cpu     486
        org     100h
bits 16
start:  cli
        cld
        mov     ax, 3000h
        mov     ds, ax
        mov     ss, ax
        xor     ebp, ebp
        mov     cx, 400h                ; rounds
        mov     di, 0B756h              ; stack top as in the game
        xor     si, si
.round: mov     sp, di
        mov     bx, sp
        mov     word [ss:bx+6], 1234h   ; the caller's [bp+6]
        mov     word [si+7306h], 0E62h
        push    bp
        mov     bp, bx
        push    word [bp+6]
        push    word 0Ah
        push    word 0
        push    word 0
        push    word [si+7306h]
        mov     ax, 5555h
        push    ax
        mov     bx, sp
        cmp     word [ss:bx+0], 5555h
        jne     .bad
        cmp     word [ss:bx+2], 0E62h
        jne     .bad
        cmp     word [ss:bx+4], 0
        jne     .bad
        cmp     word [ss:bx+6], 0
        jne     .bad
        cmp     word [ss:bx+8], 0Ah
        jne     .bad
        cmp     word [ss:bx+10], 1234h
        jne     .bad
        add     sp, 12
        pop     bp
        cmp     sp, di
        jne     .bad
        inc     ebp
        add     si, 36h                 ; next array element (a new line)
        sub     di, 2                   ; and a new stack position
        loop    .round
        mov     dx, 7FF0h
        mov     ax, 600Dh
        out     dx, ax
        hlt
        jmp     $
.bad:   mov     dx, 7FE4h
        mov     ax, 0BADh
        out     dx, ax
        hlt
        jmp     $
