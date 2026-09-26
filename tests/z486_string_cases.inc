; SPDX-License-Identifier: GPL-3.0-or-later
; REP fill/compare in cached and uncached conventional RAM. Exercise 16-bit
; index/count wrap with nonzero high halves, partial mismatch termination,
; and condition flags consumed after an indirect near jump.
    mov word [0x27c0], 0
    mov bx, 4000h
z486_string_bank:
    mov es, bx
    mov ax, 0ffffh
z486_string_pattern:
    inc word [0x27c0]
    mov edi, 1234fe00h
    mov ecx, 56780100h
    mov bp, z486_string_stored
    stc
    rep stosw
    jmp bp
z486_string_stored:
    jnc fail
    cmp edi, 12340000h
    jne fail
    cmp ecx, 56780000h
    jne fail

    ; Watcom C 9.x emits F2 (REPNE) before STOS. STOS ignores ZF, so it must
    ; fill and count exactly like F3 REP, including the architectural eCX.
    inc word [0x27c0]
    mov edi, 1234fe00h
    mov ecx, 56780100h
    mov bp, z486_string_repne_stored
    cmp cx, cx                ; ZF=1 must not end REPNE STOS.
    repne stosw
    jmp bp
z486_string_repne_stored:
    jne fail
    cmp edi, 12340000h
    jne fail
    cmp ecx, 56780000h
    jne fail

    inc word [0x27c0]
    mov dx, ax
    shl eax, 16
    mov ax, dx                ; Keep every stored word equal to AX.
    mov edi, 1234fe00h
    mov ecx, 56780080h
    mov bp, z486_string_repne_dword
    cmp cx, cx
    repne stosd
    jmp bp
z486_string_repne_dword:
    jne fail
    cmp edi, 12340000h
    jne fail
    cmp ecx, 56780000h
    jne fail

    inc word [0x27c0]
    mov edi, 1234fe00h
    mov ecx, 56780100h
    mov bp, z486_string_equal
    cmp cx, 0                 ; REPE must execute first iteration with ZF=0.
    repe scasw
    jmp bp
z486_string_equal:
    jne fail
    cmp edi, 12340000h
    jne fail
    cmp ecx, 56780000h
    jne fail

    inc word [0x27c0]
    not word [es:0ff00h]
    mov edi, 1234fe00h
    mov ecx, 56780100h
    mov bp, z486_string_mismatch
    cmp cx, cx
    repe scasw
    jmp bp
z486_string_mismatch:
    je fail
    cmp edi, 1234ff02h
    jne fail
    cmp ecx, 5678007fh
    jne fail
    sub ax, 5555h
    jnc z486_string_pattern
    cmp bx, 8000h
    je z486_string_done
    mov bx, 8000h
    jmp z486_string_bank
z486_string_done:
    push ds
    pop es
    mov word [0x27c0], 25
