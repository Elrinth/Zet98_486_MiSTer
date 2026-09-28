; SPDX-License-Identifier: GPL-3.0-or-later
; Steam Heart's ST1.EXE 25E3:1569 exactly (B216 stack-write trace): on the
; MiSTer the three register pushes between PUSH [BP+6] and PUSH [SI+7306h]
; were lost (no store, SP unchanged), so ADD SP,0Ch later left SP 6 high.
;   push [bp+6] / mov ax,0Ah / push ax / sub ax,ax / push ax / push ax /
;   push [si+7306h] / mov ax,[si+7304h] / mov cl,3 / shl ax,cl / add ax,30h /
;   push ax / call far / add sp,0Ch
; Each round moves SI to a new 36h-byte element (first read of the line) and
; the frame by a word. The callee records the SP it sees and the six words.
; Built as a flat binary loaded at 1000:0100 (simulation) or as a .COM
; (-DCOM: prints OK or BAD and the round, then returns to DOS).
        cpu     486
        org     100h
bits 16
start:  cld
        push    cs
        pop     ds
%ifdef COM
        mov     ax, cs
        add     ax, 1000h
        mov     [dseg], ax
%else
        cli
        mov     word [dseg], 3000h
%endif
        mov     [callee_seg], cs
        push    ds
        mov     [save_ss], ss
        mov     [save_sp], sp
        ; Fill every element first; each round then evicts the L1 before use.
        mov     ds, [cs:dseg]
        xor     si, si
        mov     cx, 100h
.fill:  mov     word [si+7306h], 0700h
        mov     word [si+7304h], 0300h
        add     si, 36h
        loop    .fill
        xor     ebp, ebp
        mov     cx, 100h                ; rounds (arrays stay below the frames)
        mov     di, 0B756h              ; frame top as in the game
        xor     si, si
.round: push    cx
        push    di
        mov     ax, [cs:dseg]
        mov     ds, ax
        mov     ss, ax
        mov     sp, di
        mov     bx, di
        mov     word [ss:bx+4], 0E62h   ; [bp+6] once BP is pushed
        push    ds                      ; read 32 KB elsewhere: both operand
        mov     ax, ds                  ; reads below miss the L1
        add     ax, 1000h
        mov     ds, ax
        push    si
        xor     si, si
        mov     cx, 800h
.evict: mov     ax, [si]
        add     si, 10h
        loop    .evict
        pop     si
        pop     ds
        push    bp
        mov     bp, sp
        push    word [bp+6]
        mov     ax, 0Ah
        push    ax
        sub     ax, ax
        push    ax
        push    ax
        push    word [si+7306h]
        mov     ax, [si+7304h]
        mov     cl, 3
        shl     ax, cl
        add     ax, 30h
        push    ax
        call    far [cs:callee_ptr]
        add     sp, 0Ch
        pop     bp
        mov     dx, sp
        mov     ss, [cs:save_ss]
        mov     sp, [cs:save_sp]
        sub     sp, 4                   ; the pushed CX/DI below save_sp
        pop     di
        pop     cx
        cmp     dx, di
        jne     .bad
        cmp     byte [cs:callee_bad], 0
        jne     .bad
        inc     ebp
        add     si, 36h
        sub     di, 2
        loop    .round
        pop     ds
%ifdef COM
        mov     dx, msg_ok
        mov     ah, 9
        int     21h
        mov     ax, 4C00h
        int     21h
%else
        mov     dx, 7FF0h
        mov     ax, 600Dh
        out     dx, ax
        hlt
        jmp     $
%endif
.bad:   mov     ss, [cs:save_ss]
        mov     sp, [cs:save_sp]
        pop     ds
%ifdef COM
        mov     ax, bp                  ; round number
        mov     di, msg_round
        mov     cx, 4
.hex:   rol     ax, 4
        mov     bl, al
        and     bl, 0Fh
        add     bl, '0'
        cmp     bl, '9'
        jbe     .dig
        add     bl, 7
.dig:   mov     [di], bl
        inc     di
        loop    .hex
        mov     dx, msg_bad
        mov     ah, 9
        int     21h
        mov     ax, 4C01h
        int     21h
%else
        mov     dx, 7FE4h
        mov     ax, 0BADh
        out     dx, ax
        hlt
        jmp     $
%endif

; Far callee: SP must be the frame top - 2 (BP) - 12 (args) - 4 (return).
callee: push    bp
        mov     bp, sp
        mov     byte [cs:callee_bad], 0
        mov     ax, [bp+6]              ; last pushed: (0300h << 3) + 30h
        cmp     ax, 1830h
        jne     .no
        cmp     word [bp+8], 0700h
        jne     .no
        cmp     word [bp+10], 0
        jne     .no
        cmp     word [bp+12], 0
        jne     .no
        cmp     word [bp+14], 0Ah
        jne     .no
        cmp     word [bp+16], 0E62h
        jne     .no
        pop     bp
        retf
.no:    mov     byte [cs:callee_bad], 1
        pop     bp
        retf

callee_ptr:     dw callee
callee_seg:     dw 0
dseg:           dw 0
save_sp:        dw 0
save_ss:        dw 0
callee_bad:     db 0
msg_ok:         db 'PUSHREG OK', 13, 10, '$'
msg_bad:        db 'PUSHREG BAD round '
msg_round:      db '0000', 13, 10, '$'
