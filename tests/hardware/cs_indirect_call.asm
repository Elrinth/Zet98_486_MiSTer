; SPDX-License-Identifier: GPL-3.0-or-later
; PCMDRV-style INT dispatcher (Steam Heart's): the handler saves registers into
; its code segment with CS: overrides, restores the caller's IF with
; PUSH [BP+6]/POPF, dispatches CALL WORD PTR CS:[BX] through a table while
; DS/ES point elsewhere, restores everything from CS: and returns with IRET.
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
        xor     ax, ax
        mov     es, ax
        mov     word [es:0D5h*4], handler
        mov     [es:0D5h*4+2], cs
        mov     cx, 300
.loop:  mov     ax, 2000h               ; caller's DS/ES differ from CS
        mov     ds, ax
        mov     es, ax
        mov     ax, cx
        and     ax, 3
        mov     ah, al                  ; function 0-3
        mov     al, cl
        mov     bx, 1111h
        mov     dx, 2222h
        mov     si, 3333h
        mov     di, 4444h
        mov     bp, 5555h
        sti
        int     0D5h
        cli
        mov     ebp, 1
        cmp     bx, 1111h
        jne     fail
        cmp     dx, 2222h
        jne     fail
        cmp     si, 3333h
        jne     fail
        cmp     di, 4444h
        jne     fail
        mov     ebp, 2
        mov     bx, ds
        cmp     bx, 2000h
        jne     fail
        mov     bx, es
        cmp     bx, 2000h
        jne     fail
        ; the called function stored AH+1 in AL
        mov     ebp, 3
        mov     bl, cl
        and     bl, 3
        inc     bl
        cmp     al, bl
        jne     fail
        mov     ebp, 4
        cmp     sp, 0FFF0h
        jne     fail
        loop    .loop
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

; ---- the dispatcher (same shape as PCMDRV's) ----
handler:
        push    bp
        mov     bp, sp
        push    word [bp+6]
        popf
        pop     bp
        mov     [cs:s_ax], ax
        mov     [cs:s_bx], bx
        mov     [cs:s_cx], cx
        mov     [cs:s_dx], dx
        mov     [cs:s_si], si
        mov     [cs:s_di], di
        mov     [cs:s_bp], bp
        mov     [cs:s_ds], ds
        mov     [cs:s_es], es
        cmp     ah, 4
        jae     .bad
        mov     bx, table
        mov     al, ah
        mov     ah, 0
        add     bx, ax
        add     bx, ax
        call    word [cs:bx]
.ret:   mov     ax, [cs:s_ax]
        mov     bx, [cs:s_bx]
        mov     cx, [cs:s_cx]
        mov     dx, [cs:s_dx]
        mov     si, [cs:s_si]
        mov     di, [cs:s_di]
        mov     bp, [cs:s_bp]
        mov     ds, [cs:s_ds]
        mov     es, [cs:s_es]
        iret
.bad:   mov     byte [cs:s_ax], 0FFh
        jmp     .ret

f0:     mov     byte [cs:s_ax], 1
        ret
f1:     mov     byte [cs:s_ax], 2
        ret
f2:     mov     byte [cs:s_ax], 3
        ret
f3:     mov     byte [cs:s_ax], 4
        ret
table:  dw      f0, f1, f2, f3
s_ax:   dw      0
s_bx:   dw      0
s_cx:   dw      0
s_dx:   dw      0
s_si:   dw      0
s_di:   dw      0
s_bp:   dw      0
s_ds:   dw      0
s_es:   dw      0
