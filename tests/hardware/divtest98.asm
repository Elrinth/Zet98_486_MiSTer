; SPDX-License-Identifier: GPL-3.0-or-later
; DIVTEST.COM [rounds]: random DIV/IDIV (16- and 32-bit) against a shift-and-
; subtract reference that uses no divide instruction. Written after a build
; where COMMAND.COM raised "divide by zero" on long command lines.
; Each round: 4096 unsigned 16-bit (DX:AX / r16), 4096 unsigned 32-bit
; (EDX:EAX / r32), 4096 signed 32-bit IDIV. Quotients that would overflow are
; skipped (the reference decides). Prints failures (max 10) and totals.
        cpu     386
        org     100h
bits 16
start:  cld
        mov     dx, title
        call    puts
        mov     si, 81h                 ; rounds (decimal), default 8
        xor     ax, ax
.arg:   mov     bl, [si]
        inc     si
        cmp     bl, ' '
        je      .arg
        sub     bl, '0'
        cmp     bl, 9
        ja      .argdone
.dig:   imul    ax, 10
        xor     bh, bh
        add     ax, bx
        mov     bl, [si]
        inc     si
        sub     bl, '0'
        cmp     bl, 9
        jbe     .dig
.argdone:
        test    ax, ax
        jnz     .have
        mov     ax, 8
.have:  mov     [rounds], ax
        ; catch #DE from our own divides (should never happen: overflow cases are skipped)
        push    es
        xor     ax, ax
        mov     es, ax
        mov     eax, [es:0]
        mov     [old_de], eax
        mov     word [es:0], de_handler
        mov     [es:2], cs
        pop     es

.round: mov     cx, 4096
.u16:   push    cx
        call    rnd32
        mov     [dividend], eax
        call    rnd32
        mov     [dividend+4], eax
        call    rnd32                   ; divisor: random size 1..16 bits
        mov     ecx, eax
        call    rnd32
        and     cl, 15
        inc     cl
        mov     ebx, 1
        shl     ebx, cl
        dec     ebx
        and     eax, ebx
        jnz     .u16d
        inc     eax
.u16d:  mov     [divisor], eax
        ; 16-bit: dividend = DX:AX (32 bits), divisor 16 bits
        mov     eax, [dividend]
        movzx   ebx, word [divisor]
        xor     edx, edx
        call    ref_udiv                ; EDX:EAX / EBX -> quotient EAX, rem EDX (64/32 unsigned)
        cmp     eax, 0FFFFh
        ja      .u16skip                ; would overflow: #DE on hardware
        mov     [exp_q], eax
        mov     [exp_r], edx
        mov     ax, [dividend]
        mov     dx, [dividend+2]
        mov     bx, [divisor]
        div     bx
        movzx   eax, ax
        movzx   edx, dx
        mov     byte [kind], 1
        call    compare
.u16skip:
        inc     dword [tests]
        pop     cx
        dec     cx
        jnz     .u16

        mov     cx, 4096
.u32:   push    cx
        call    rnd32
        mov     [dividend], eax
        call    rnd32
        mov     [dividend+4], eax
        call    rnd32
        mov     ecx, eax
        call    rnd32
        and     cl, 31
        inc     cl
        mov     ebx, 0FFFFFFFFh
        cmp     cl, 32
        je      .full
        mov     ebx, 1
        shl     ebx, cl
        dec     ebx
.full:  and     eax, ebx
        jnz     .u32d
        inc     eax
.u32d:  mov     [divisor], eax
        ; keep the high dword below the divisor so the quotient fits (no #DE):
        ; high := high mod divisor, computed by the reference, not by DIV
        mov     eax, [dividend+4]
        xor     edx, edx
        mov     ebx, [divisor]
        call    ref_udiv
        mov     [dividend+4], edx
        mov     eax, [dividend]
        mov     edx, [dividend+4]
        mov     ebx, [divisor]
        call    ref_udiv
        mov     [exp_q], eax
        mov     [exp_r], edx
        mov     eax, [dividend]
        mov     edx, [dividend+4]
        div     dword [divisor]
        mov     byte [kind], 2
        call    compare
        inc     dword [tests]
        pop     cx
        dec     cx
        jnz     .u32

        mov     cx, 4096
.s32:   push    cx
        call    rnd32                   ; signed 32-bit dividend (sign-extended into EDX)
        mov     [dividend], eax
        call    rnd32
        mov     ecx, eax
        call    rnd32
        and     cl, 31
        inc     cl
        mov     ebx, 1
        shl     ebx, cl
        dec     ebx
        and     eax, ebx
        jnz     .s32d
        inc     eax
.s32d:  test    ch, 1
        jz      .s32p
        neg     eax
.s32p:  mov     [divisor], eax
        ; reference: |a| / |b| unsigned, then fix signs (truncate toward 0)
        mov     eax, [dividend]
        mov     ebx, [divisor]
        mov     esi, eax
        xor     esi, ebx                ; sign of quotient in bit 31
        mov     edi, eax                ; sign of remainder = sign of dividend
        test    eax, eax
        jns     .a
        neg     eax
.a:     test    ebx, ebx
        jns     .b
        neg     ebx
.b:     xor     edx, edx
        call    ref_udiv
        test    esi, esi
        jns     .qs
        neg     eax
.qs:    test    edi, edi
        jns     .rs
        neg     edx
.rs:    mov     [exp_q], eax
        mov     [exp_r], edx
        mov     eax, [dividend]
        cdq
        idiv    dword [divisor]
        mov     byte [kind], 3
        cmp     dword [dividend], 80000000h ; -2^31 / -1 overflows: skip
        jne     .scmp
        cmp     dword [divisor], -1
        je      .sskip
.scmp:  call    compare
.sskip: inc     dword [tests]
        pop     cx
        dec     cx
        jnz     .s32

        inc     word [done]
        mov     dx, t_round
        call    puts
        mov     ax, [done]
        call    putdec
        mov     dx, t_fails
        call    puts
        mov     ax, [fails]
        call    putdec
        mov     dx, crlf
        call    puts
        mov     ax, [done]
        cmp     ax, [rounds]
        jb      .round

        push    es
        xor     ax, ax
        mov     es, ax
        mov     eax, [old_de]
        mov     [es:0], eax
        pop     es
        mov     dx, t_pass
        cmp     word [fails], 0
        je      .out
        mov     dx, t_fail
.out:   call    puts
        mov     ax, 4C00h
        int     21h

; EDX:EAX / EBX with EDX < EBX (quotient fits 32 bits) -> EAX quotient,
; EDX remainder. Restoring shift/subtract; no divide instruction.
ref_udiv:
        push    ecx
        push    esi
        mov     esi, eax                ; dividend low dword, shifted out bit by bit
        xor     eax, eax                ; quotient
        mov     cx, 32
.l:     shl     esi, 1
        rcl     edx, 1                  ; remainder:next bit; CF = 33rd remainder bit
        jc      .sub
        cmp     edx, ebx
        jb      .zero
.sub:   sub     edx, ebx
        stc
        rcl     eax, 1
        jmp     .n
.zero:  shl     eax, 1
.n:     loop    .l
        pop     esi
        pop     ecx
        ret

; got quotient EAX / remainder EDX vs exp_q / exp_r
compare:
        cmp     eax, [exp_q]
        jne     .bad
        cmp     edx, [exp_r]
        jne     .bad
        ret
.bad:   pushad
        inc     word [fails]
        cmp     word [fails], 10
        ja      .quiet
        mov     [got_q], eax
        mov     [got_r], edx
        movzx   bx, byte [kind]
        shl     bx, 1
        mov     dx, [kinds + bx - 2]
        call    puts
        mov     eax, [dividend+4]
        call    puthex32
        mov     dl, ':'
        call    putc
        mov     eax, [dividend]
        call    puthex32
        mov     dl, '/'
        call    putc
        mov     eax, [divisor]
        call    puthex32
        mov     dx, t_got
        call    puts
        mov     eax, [got_q]
        call    puthex32
        mov     dl, 'r'
        call    putc
        mov     eax, [got_r]
        call    puthex32
        mov     dx, t_exp
        call    puts
        mov     eax, [exp_q]
        call    puthex32
        mov     dl, 'r'
        call    putc
        mov     eax, [exp_r]
        call    puthex32
        mov     dx, crlf
        call    puts
.quiet: popad
        ret

de_handler:                             ; unexpected #DE: count and skip the 2-4 byte DIV
        push    bp
        mov     bp, sp
        push    ax
        push    si
        push    ds
        push    cs
        pop     ds
        inc     word [fails]
        inc     word [de_count]
        mov     si, [bp+2]              ; faulting IP
        mov     ds, [bp+4]
        cmp     byte [si], 66h
        jne     .n66
        inc     word [bp+2]
        inc     si
.n66:   add     word [bp+2], 2          ; F7 /6 or /7 with a register operand
        mov     al, [si+1]
        and     al, 0C7h
        cmp     al, 06h                 ; [disp16] operand: two more bytes
        jne     .done
        add     word [bp+2], 2
.done:  pop     ds
        pop     si
        pop     ax
        pop     bp
        iret

rnd32:  ; xorshift32
        mov     eax, [seed]
        mov     edx, eax
        shl     edx, 13
        xor     eax, edx
        mov     edx, eax
        shr     edx, 17
        xor     eax, edx
        mov     edx, eax
        shl     edx, 5
        xor     eax, edx
        mov     [seed], eax
        ret

puts:   push    ax
        mov     ah, 09h
        int     21h
        pop     ax
        ret
putc:   push    ax
        mov     ah, 02h
        int     21h
        pop     ax
        ret
puthex32:
        pushad
        mov     cx, 8
.d:     rol     eax, 4
        mov     dl, al
        and     dl, 0Fh
        add     dl, '0'
        cmp     dl, '9'
        jbe     .p
        add     dl, 7
.p:     call    putc
        loop    .d
        popad
        ret
putdec: pusha
        xor     cx, cx
        mov     bx, 10
.div:   xor     dx, dx
        div     bx
        push    dx
        inc     cx
        test    ax, ax
        jnz     .div
.out:   pop     dx
        add     dl, '0'
        call    putc
        loop    .out
        popa
        ret

title   db 'DIVTEST (PC98-486 DIV/IDIV check)', 13, 10, '$'
k_u16   db 'DIV r16 $'
k_u32   db 'DIV r32 $'
k_s32   db 'IDIV r32 $'
kinds   dw k_u16, k_u32, k_s32
t_got   db ' got $'
t_exp   db ' exp $'
t_round db 'Round $'
t_fails db ' done, failures $'
t_pass  db 'DIVTEST PASS', 13, 10, '$'
t_fail  db 'DIVTEST FAIL', 13, 10, '$'
crlf    db 13, 10, '$'
seed    dd 2463534242
rounds  dw 8
done    dw 0
fails   dw 0
de_count dw 0
tests   dd 0
old_de  dd 0
kind    db 0
dividend dd 0, 0
divisor dd 0
exp_q   dd 0
exp_r   dd 0
got_q   dd 0
got_r   dd 0
