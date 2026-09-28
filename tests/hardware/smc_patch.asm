; SPDX-License-Identifier: GPL-3.0-or-later
; Self-modifying code as Flame Zapper Kotsujin's sprite routine uses it:
; immediates of MOV/ADD instructions are patched through SS: before a CALL,
; and the routine patches its own MOV BP immediate with ADD WORD [CS:..]
; right after executing it. A real 486 always runs the patched values (the
; CALL/RET flushes the prefetch queue; the unified cache holds the new code).
; Loaded at 1000:0100. Reports 600Dh to port 7FF0h on success; on failure
; EBP holds the failure code and 0BADh goes to port 7FE4h.
        cpu     486
        org     100h

bits 16
start:  cli
        cld
        mov     ax, cs
        mov     ds, ax
        mov     ss, ax
        mov     sp, 0FFF0h
        xor     ax, ax
        out     0F2h, al                ; PC-98: A20 on (harmless here)

        ; Warm the routine into the instruction cache first.
        call    routine
        call    routine

        mov     cx, 256                 ; iterations
        mov     di, 1234h               ; running pattern
.loop:  ; patch the immediates (SS: override, as the game does)
        mov     [ss:p_ax], di
        lea     si, [di+1111h]
        mov     [ss:p_dx], si
        lea     bx, [di+2222h]
        mov     [ss:p_bp], bx
        mov     word [ss:p_add], 0010h  ; ADD BP step used inside the routine
        ; a variable number of filler instructions between patch and call
        mov     ax, cx
        and     ax, 7
.fill:  dec     ax
        jns     .fill
        call    routine                 ; returns AX, DX, BP as executed
        cmp     ax, di
        jne     .bad_ax
        lea     si, [di+1111h]
        cmp     dx, si
        jne     .bad_dx
        lea     bx, [di+2222h+10h]      ; MOV BP value plus the ADD BP step
        cmp     bp, bx
        jne     .bad_bp
        ; the routine incremented its own MOV BP immediate by 20h via CS:
        lea     bx, [di+2222h+20h]
        cmp     [p_bp], bx
        jne     .bad_self
        ; second call without re-patching: must see the self-patched value
        call    routine
        lea     bx, [di+2222h+20h+10h]
        cmp     bp, bx
        jne     .bad_again
        add     di, 0137h
        loop    .loop

        mov     dx, 7FF0h
        mov     ax, 600Dh
        out     dx, ax
        hlt
        jmp     $

.bad_ax:   mov ebp, 1
           jmp  fail
.bad_dx:   mov ebp, 2
           jmp  fail
.bad_bp:   mov ebp, 3
           jmp  fail
.bad_self: mov ebp, 4
           jmp  fail
.bad_again: mov ebp, 5
fail:   mov     dx, 7FE4h
        mov     ax, 0BADh
        out     dx, ax
        hlt
        jmp     $

; The patched routine (same shape as the game's: MOV AX/DX/BP imm16, then
; an ADD BP imm16 and an ADD WORD [CS:] into its own MOV BP immediate).
        align   16
routine:
        db      0B8h                    ; mov ax, imm16
p_ax:   dw      0
        db      0BAh                    ; mov dx, imm16
p_dx:   dw      0
        db      0BDh                    ; mov bp, imm16
p_bp:   dw      0
        db      81h, 0C5h               ; add bp, imm16
p_add:  dw      0
        add     word [cs:p_bp], 0020h
        ret
