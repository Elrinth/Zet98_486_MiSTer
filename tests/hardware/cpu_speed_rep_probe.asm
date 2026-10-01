; SPDX-License-Identifier: GPL-3.0-or-later
; REP string instructions under the z486 execution-rate throttle. At slow
; settings a long REP leaves its loop through the interrupt/restart exit
; whenever its debt is high and is refetched with the remaining count, so
; every form must give exact data, final pointers, count and flags across
; many restarts, with and without real timer interrupts (IRQ0 is unmasked;
; the PIT_PM_TEST testbench raises it every 10000 clocks).
; Loaded at 1000:0100 (DOS_PROBE=1). Buffers in 4000h/5000h, results in
; 6000h:0000 for the RAM dump.
; Success: 600Dh to port 7FF0h. Failure: EBP=stage, 0BADh to port 7FF0h.
        cpu     486
        org     100h
bits 16

N       equ     6000                    ; elements per long REP
SEGA    equ     4000h
SEGB    equ     5000h
SEGR    equ     6000h

%macro  check 2                         ; stage, condition-false jump
        mov     ebp, %1
        %2      fail
%endmacro

start:  cli
        cld
        mov     ax, cs
        mov     ss, ax
        mov     sp, 0FFF0h
        xor     ax, ax
        mov     ds, ax
        mov     word [08h*4], irq0
        mov     [08h*4+2], cs
        mov     al, 0FEh
        out     02h, al
        sti

        ; 1: REP STOSW pattern fill of A, verified by a plain loop
        mov     ax, SEGA
        mov     es, ax
        xor     di, di
        mov     cx, N
        mov     ax, 0A55Ah
        rep     stosw
        mov     ebp, 1
        test    cx, cx
        jnz     fail
        cmp     di, N*2
        check   2, jne
        mov     ax, SEGA
        mov     ds, ax
        xor     si, si
        mov     cx, N
.v1:    cmp     word [si], 0A55Ah
        check   3, jne
        add     si, 2
        loop    .v1

        ; 2: distinct bytes in A (plain loop), REP MOVSB A->B forward
        xor     si, si
        mov     cx, N*2
        xor     al, al
.f2:    mov     [si], al
        add     al, 7
        inc     si
        loop    .f2
        mov     ax, SEGB
        mov     es, ax
        xor     si, si
        xor     di, di
        mov     cx, N*2
        rep     movsb
        cmp     si, N*2
        check   4, jne
        cmp     di, N*2
        check   5, jne
        call    compare_ab
        check   6, jne

        ; 3: REP MOVSD backward (STD) B->A over a fresh pattern in B
        xor     di, di
        mov     cx, N/2
        mov     eax, 12345678h
.f3:    mov     [es:di], eax
        add     eax, 9E3779B9h
        add     di, 4
        loop    .f3
        mov     ax, es                  ; DS=B, ES=A
        mov     bx, ds
        mov     ds, ax
        mov     es, bx
        std
        mov     si, N*2-4
        mov     di, N*2-4
        mov     cx, N/2
        rep     movsd
        cld
        cmp     si, -4
        check   7, jne
        cmp     di, -4
        check   8, jne
        mov     ax, SEGA
        mov     ds, ax
        mov     ax, SEGB
        mov     es, ax
        call    compare_ab
        check   9, jne

        ; 4: REPE CMPSW, first difference at word K
K       equ     4321
        xor     byte [es:K*2+1], 80h
        xor     si, si
        xor     di, di
        mov     cx, N
        repe    cmpsw
        check   10, je                  ; must stop on the mismatch (ZF=0)
        cmp     si, (K+1)*2
        check   11, jne
        cmp     di, (K+1)*2
        check   12, jne
        cmp     cx, N-K-1
        check   13, jne
        xor     byte [es:K*2+1], 80h

        ; 5: REPNE SCASB for a byte that only occurs at offset P
P       equ     9876
        xor     di, di
        mov     cx, N*2
        mov     al, 0FFh
        rep     stosb
        mov     byte [es:P], 3Ch
        xor     di, di
        mov     cx, N*2
        mov     al, 3Ch
        repne   scasb
        check   14, jne                 ; found (ZF=1)
        cmp     di, P+1
        check   15, jne
        cmp     cx, N*2-P-1
        check   16, jne

        ; 6: REP LODSW leaves the last word, SI and CX exact
        xor     si, si
        mov     cx, N
        rep     lodsw
        cmp     si, N*2
        check   17, jne
        cmp     ax, [N*2-2]
        check   18, jne
        test    cx, cx
        check   19, jnz
        ; 7: a32 REP STOSD with 32-bit count/index
        mov     edi, 0
        mov     ecx, N/2
        mov     eax, 0C0FFEE00h
        a32 rep stosd
        cmp     edi, N*2
        check   20, jne
        test    ecx, ecx
        check   21, jnz
        mov     ax, SEGB
        mov     ds, ax
        cmp     dword [N*2-4], 0C0FFEE00h
        check   22, jne

        cli
        mov     al, 0FFh
        out     02h, al
        ; publish a signature for the cross-speed RAM dump comparison
        mov     ax, SEGR
        mov     es, ax
        xor     di, di
        mov     ax, SEGA
        mov     ds, ax
        xor     si, si
        mov     cx, 256
        rep     movsw
        mov     dx, 7FF0h
        mov     ax, 600Dh
        out     dx, ax
        hlt
        jmp     $

; ZF=1 when DS:0 and ES:0 match over N*2 bytes (plain loop, no REP)
compare_ab:
        xor     si, si
        mov     cx, N
.c:     mov     ax, [si]
        cmp     ax, [es:si]
        jne     .done
        add     si, 2
        loop    .c
        xor     ax, ax                  ; ZF=1
.done:  ret

irq0:   inc     word [cs:ticks]
        push    ax
        mov     al, 20h
        out     00h, al
        pop     ax
        iret

fail:   cli
        mov     dx, 7FF0h
        mov     ax, 0BADh
        out     dx, ax
        hlt
        jmp     $

ticks:  dw      0
