; SPDX-License-Identifier: GPL-3.0-or-later
; CPU speed (execution-rate throttle) probe for the z486 XMS testbench.
; A deterministic mix of ALU, IMUL, ROL, cached loads/stores, PUSH/POP,
; CALL/RET, LOOP and a short REP MOVSW. The result must be identical at
; every throttle setting; tests/run-z486-cpu-speed.sh also checks how the
; wall-clock cycle count scales. The expected checksum is computed by the
; assembler. Loaded at 1000:0100 (DOS_PROBE=1). Data, stack and the copy
; buffer live in segment 4000h so the RAM dump covers them.
; Success: 600Dh to port 7FF0h. Failure: EBP=stage, 0BADh to port 7FF0h.
        cpu     486
        org     100h
bits 16

%ifndef ITER
%define ITER 600
%endif

; Assembler model of the loop: ebx = rol(ebx + i*i, 3) ^ i for i = ITER..1
%assign X 0
%assign I ITER
%rep ITER
  %assign X ((X + I*I) & 0xFFFFFFFF)
  %assign X ((((X << 3) & 0xFFFFFFFF) | (X >> 29)) & 0xFFFFFFFF)
  %assign X (X ^ I)
  %assign I I-1
%endrep

start:  cli
        cld
        mov     ax, 4000h
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, 0FFF0h
        xor     ebx, ebx
        mov     dword [calls], 0
        ; source block for the per-iteration REP MOVSW
        mov     di, src
        mov     cx, 16
        mov     ax, 1234h
.fill:  stosw
        add     ax, 0F0Fh
        loop    .fill
        mov     cx, ITER
.loop:  movzx   eax, cx
        imul    eax, eax
        add     ebx, eax
        rol     ebx, 3
        xor     bx, cx
        ; store / reload through the data cache
        mov     di, cx
        and     di, 0FFh
        shl     di, 2
        mov     [table+di], ebx
        mov     edx, [table+di]
        mov     ebp, 1
        cmp     edx, ebx
        jne     fail
        ; stack and near call
        push    ebx
        push    cx
        call    count
        pop     cx
        pop     edx
        mov     ebp, 2
        cmp     edx, ebx
        jne     fail
        ; short string copy
        push    cx
        mov     si, src
        mov     di, dst
        mov     cx, 16
        rep     movsw
        pop     cx
        mov     ax, [dst+30]
        mov     ebp, 3
        cmp     ax, [src+30]
        jne     fail
        dec     cx
        jnz     .loop
        mov     ebp, 4
        cmp     ebx, X
        jne     fail
        mov     ebp, 5
        cmp     dword [calls], ITER
        jne     fail
        mov     [result], ebx
        mov     dx, 7FF0h
        mov     ax, 600Dh
        out     dx, ax
        hlt
        jmp     $

count:  inc     dword [calls]
        ret

fail:   mov     dx, 7FF0h
        mov     ax, 0BADh
        out     dx, ax
        hlt
        jmp     $

; data in segment 4000h (offsets only)
calls   equ     0100h
result  equ     0104h
src     equ     0200h
dst     equ     0300h
table   equ     0400h
