; SPDX-License-Identifier: GPL-3.0-or-later
; STRTEST.COM: checks the CPU's string instructions against plain-instruction
; reference loops, over many lengths, alignments and data. Written to find a
; build-specific CPU fault (COMMAND.COM mis-parsing one batch line).
; For each case the final SI/DI/CX/ZF (and copied data) must equal the
; reference computed with MOV/CMP/INC only. Prints failing cases (max 12).
;   REPNE SCASB  find a byte at every position of strings up to 140 bytes
;   REPE  SCASB  run of equal bytes, stops at a different one
;   REPE  CMPSB  compare two strings differing at every position
;   REP   MOVSB  copy lengths 0..140 at 4 source x 4 destination alignments
;   LODSB loop / STOSB loop / REP MOVSW / REP STOSB
; Both directions (CLD/STD) for SCASB and MOVSB.
        cpu     386
        org     100h
bits 16
MAXLEN  equ     140

start:  mov     dx, title
        call    puts
        push    ds
        pop     es
        call    t_repne_scasb
        call    t_repe_scasb
        call    t_repe_cmpsb
        call    t_rep_movsb
        call    t_std_scasb
        call    t_std_movsb
        call    t_lods_stos
        mov     dx, t_cases
        call    puts
        mov     ax, [cases]
        call    putdec
        mov     dx, t_fails
        call    puts
        mov     ax, [fails]
        call    putdec
        mov     dx, crlf
        call    puts
        mov     dx, t_pass
        cmp     word [fails], 0
        je      .out
        mov     dx, t_fail
.out:   call    puts
        mov     ax, 4C00h
        int     21h

; ---- REPNE SCASB: string of 'a' with 'X' at position p, search length n --------
t_repne_scasb:
        mov     word [name], n_repne
        xor     bx, bx                  ; alignment 0..3
.align: xor     bp, bp                  ; n (search length) 0..MAXLEN
.len:   mov     cx, bp
        xor     dx, dx                  ; p position of 'X' (0..n, n = absent)
.pos:   ; build buffer
        lea     di, [buf1+bx]
        push    cx
        mov     cx, MAXLEN + 8
        mov     al, 'a'
.fill:  mov     [di], al
        inc     di
        loop    .fill
        pop     cx
        lea     di, [buf1+bx]
        add     di, dx
        mov     byte [di], 'X'
        ; reference: index of first 'X' within n bytes
        lea     si, [buf1+bx]
        xor     ax, ax
.ref:   cmp     ax, bp
        je      .refnf
        mov     di, si
        add     di, ax
        cmp     byte [di], 'X'
        je      .reff
        inc     ax
        jmp     .ref
.reff:  ; found at ax: DI = start+ax+1, CX = n-ax-1, ZF=1
        lea     di, [buf1+bx]
        add     di, ax
        inc     di
        mov     [exp_di], di
        mov     di, bp
        sub     di, ax
        dec     di
        mov     [exp_cx], di
        mov     byte [exp_zf], 1
        jmp     .run
.refnf: lea     di, [buf1+bx]
        add     di, bp
        mov     [exp_di], di
        mov     word [exp_cx], 0
        mov     byte [exp_zf], 0
        cmp     bp, 0
        jne     .run
        mov     byte [exp_zf], 2        ; n = 0: flags unchanged (don't check)
.run:   lea     di, [buf1+bx]
        mov     cx, bp
        mov     al, 'X'
        cld
        cmp     al, 0                   ; ZF=0 going in
        repne   scasb
        call    check_di_cx_zf
        inc     dx
        cmp     dx, bp
        jbe     .pos
        inc     bp
        cmp     bp, MAXLEN
        jbe     .len
        inc     bx
        cmp     bx, 4
        jb      .align
        ret

; ---- REPE SCASB: run of 'a' of length p then 'b', compare n bytes with 'a' -----
t_repe_scasb:
        mov     word [name], n_repe
        xor     bx, bx
.align: xor     bp, bp
.len:   xor     dx, dx
.pos:   lea     di, [buf1+bx]
        mov     cx, MAXLEN + 8
        mov     al, 'a'
.fill:  mov     [di], al
        inc     di
        loop    .fill
        lea     di, [buf1+bx]
        add     di, dx
        mov     byte [di], 'b'
        ; reference
        cmp     dx, bp
        jae     .allequal
        lea     di, [buf1+bx]           ; mismatch at dx
        add     di, dx
        inc     di
        mov     [exp_di], di
        mov     ax, bp
        sub     ax, dx
        dec     ax
        mov     [exp_cx], ax
        mov     byte [exp_zf], 0
        jmp     .run
.allequal:
        lea     di, [buf1+bx]
        add     di, bp
        mov     [exp_di], di
        mov     word [exp_cx], 0
        mov     byte [exp_zf], 1
        cmp     bp, 0
        jne     .run
        mov     byte [exp_zf], 2
.run:   lea     di, [buf1+bx]
        mov     cx, bp
        mov     al, 'a'
        cld
        cmp     al, 0
        repe    scasb
        call    check_di_cx_zf
        inc     dx
        cmp     dx, bp
        jbe     .pos
        inc     bp
        cmp     bp, MAXLEN
        jbe     .len
        inc     bx
        cmp     bx, 4
        jb      .align
        ret

; ---- REPE CMPSB: buf1 == buf2 except at p ------------------------------------------
t_repe_cmpsb:
        mov     word [name], n_cmps
        xor     bx, bx                  ; buf1 alignment, buf2 alignment = 3-bx
.align: xor     bp, bp
.len:   xor     dx, dx
.pos:   lea     si, [buf1+bx]
        mov     di, 3
        sub     di, bx
        add     di, buf2
        mov     cx, MAXLEN + 4
        xor     al, al
.fill:  mov     [si], al
        mov     [di], al
        inc     si
        inc     di
        add     al, 37
        loop    .fill
        mov     di, 3
        sub     di, bx
        add     di, buf2
        add     di, dx
        xor     byte [di], 80h
        ; reference
        cmp     dx, bp
        jae     .same
        lea     si, [buf1+bx]
        add     si, dx
        inc     si
        mov     [exp_si], si
        mov     di, 3
        sub     di, bx
        add     di, buf2
        add     di, dx
        inc     di
        mov     [exp_di], di
        mov     ax, bp
        sub     ax, dx
        dec     ax
        mov     [exp_cx], ax
        mov     byte [exp_zf], 0
        jmp     .run
.same:  lea     si, [buf1+bx]
        add     si, bp
        mov     [exp_si], si
        mov     di, 3
        sub     di, bx
        add     di, buf2
        add     di, bp
        mov     [exp_di], di
        mov     word [exp_cx], 0
        mov     byte [exp_zf], 1
        cmp     bp, 0
        jne     .run
        mov     byte [exp_zf], 2
.run:   lea     si, [buf1+bx]
        mov     di, 3
        sub     di, bx
        add     di, buf2
        mov     cx, bp
        cld
        cmp     cx, 0FFFFh
        repe    cmpsb
        call    check_si_di_cx_zf
        inc     dx
        cmp     dx, bp
        jbe     .pos
        inc     bp
        cmp     bp, MAXLEN
        jbe     .len
        inc     bx
        cmp     bx, 4
        jb      .align
        ret

; ---- REP MOVSB: 4x4 alignments, lengths 0..MAXLEN; verify data and guards ---------
t_rep_movsb:
        mov     word [name], n_movs
        xor     bx, bx                  ; source alignment
.sa:    xor     dx, dx                  ; destination alignment
.da:    xor     bp, bp
.len:   ; source pattern, destination filled with 0EEh
        lea     si, [buf1+bx]
        mov     cx, MAXLEN + 8
        mov     al, 11h
.fs:    mov     [si], al
        inc     si
        add     al, 53
        loop    .fs
        mov     di, buf2
        mov     cx, MAXLEN + 16
.fd:    mov     byte [di], 0EEh
        inc     di
        loop    .fd
        lea     si, [buf1+bx]
        mov     di, buf2
        add     di, dx
        mov     cx, bp
        cld
        rep     movsb
        ; registers
        lea     ax, [buf1+bx]
        add     ax, bp
        mov     [exp_si], ax
        mov     ax, buf2
        add     ax, dx
        add     ax, bp
        mov     [exp_di], ax
        mov     word [exp_cx], 0
        mov     byte [exp_zf], 2
        call    check_si_di_cx_zf
        ; data and guards
        call    verify_copy
        inc     bp
        cmp     bp, MAXLEN
        jbe     .len
        inc     dx
        cmp     dx, 4
        jb      .da
        inc     bx
        cmp     bx, 4
        jb      .sa
        ret

; buf2+dx must hold n=bp bytes from buf1+bx; buf2 before and after untouched
verify_copy:
        pusha
        inc     word [cases]
        mov     di, buf2
        mov     cx, dx
        jcxz    .body
.pre:   cmp     byte [di], 0EEh
        jne     .bad
        inc     di
        loop    .pre
.body:  lea     si, [buf1+bx]
        mov     cx, bp
        jcxz    .post
.b:     mov     al, [si]
        cmp     al, [di]
        jne     .bad
        inc     si
        inc     di
        loop    .b
.post:  mov     cx, 8
.p:     cmp     byte [di], 0EEh
        jne     .bad
        inc     di
        loop    .p
        popa
        ret
.bad:   popa
        push    word [name]
        mov     word [name], n_movsdata
        call    fail_case
        pop     word [name]
        ret

; ---- STD variants ---------------------------------------------------------------
t_std_scasb:
        mov     word [name], n_stdscas
        xor     bp, bp
.len:   xor     dx, dx
.pos:   mov     di, buf1
        mov     cx, MAXLEN + 8
        mov     al, 'a'
.fill:  mov     [di], al
        inc     di
        loop    .fill
        ; search downward from buf1+MAXLEN for n bytes, 'X' at buf1+MAXLEN-p
        mov     di, buf1 + MAXLEN
        sub     di, dx
        mov     byte [di], 'X'
        cmp     dx, bp
        jae     .nf
        mov     ax, buf1 + MAXLEN - 1
        sub     ax, dx
        mov     [exp_di], ax
        mov     ax, bp
        sub     ax, dx
        dec     ax
        mov     [exp_cx], ax
        mov     byte [exp_zf], 1
        jmp     .run
.nf:    mov     ax, buf1 + MAXLEN
        sub     ax, bp
        mov     [exp_di], ax
        mov     word [exp_cx], 0
        mov     byte [exp_zf], 0
        cmp     bp, 0
        jne     .run
        mov     byte [exp_zf], 2
.run:   mov     di, buf1 + MAXLEN
        mov     cx, bp
        mov     al, 'X'
        std
        cmp     al, 0
        repne   scasb
        cld
        call    check_di_cx_zf
        inc     dx
        cmp     dx, bp
        jbe     .pos
        inc     bp
        cmp     bp, MAXLEN
        jbe     .len
        ret

t_std_movsb:
        mov     word [name], n_stdmovs
        xor     bp, bp
.len:   mov     si, buf1
        mov     cx, MAXLEN + 8
        mov     al, 5
.fs:    mov     [si], al
        inc     si
        add     al, 29
        loop    .fs
        mov     di, buf2
        mov     cx, MAXLEN + 16
.fd:    mov     byte [di], 0EEh
        inc     di
        loop    .fd
        ; copy n bytes ending at buf1+MAXLEN -> ending at buf2+MAXLEN
        mov     si, buf1 + MAXLEN
        mov     di, buf2 + MAXLEN
        mov     cx, bp
        std
        rep     movsb
        cld
        mov     ax, buf1 + MAXLEN
        sub     ax, bp
        mov     [exp_si], ax
        mov     ax, buf2 + MAXLEN
        sub     ax, bp
        mov     [exp_di], ax
        mov     word [exp_cx], 0
        mov     byte [exp_zf], 2
        call    check_si_di_cx_zf
        ; data: buf2[MAXLEN-n+1 .. MAXLEN] == buf1[same]
        inc     word [cases]
        mov     cx, bp
        jcxz    .next
        mov     si, buf1 + MAXLEN
        mov     di, buf2 + MAXLEN
.c:     mov     al, [si]
        cmp     al, [di]
        jne     .bad
        dec     si
        dec     di
        loop    .c
        cmp     byte [di], 0EEh
        je      .next
.bad:   call    fail_case
.next:  inc     bp
        cmp     bp, MAXLEN
        jbe     .len
        ret

; ---- LODSB/STOSB loops, REP STOSB, REP MOVSW ----------------------------------------
t_lods_stos:
        mov     word [name], n_lods
        xor     bp, bp
.len:   mov     si, buf1
        mov     cx, MAXLEN
        mov     al, 3
.fs:    mov     [si], al
        inc     si
        add     al, 71
        loop    .fs
        ; LODSB + STOSB loop copying bp bytes, uppercasing letters like COMMAND.COM
        mov     si, buf1
        mov     di, buf2
        mov     cx, bp
        cld
        jcxz    .done
.l:     lodsb
        cmp     al, 'a'
        jb      .s
        cmp     al, 'z'
        ja      .s
        sub     al, 20h
.s:     stosb
        loop    .l
.done:  ; reference check
        inc     word [cases]
        mov     cx, bp
        jcxz    .regs
        mov     si, buf1
        mov     di, buf2
.c:     mov     al, [si]
        cmp     al, 'a'
        jb      .e
        cmp     al, 'z'
        ja      .e
        sub     al, 20h
.e:     cmp     al, [di]
        jne     .bad
        inc     si
        inc     di
        loop    .c
.regs:  inc     bp
        cmp     bp, MAXLEN
        jbe     .len
        ; REP STOSB and REP MOVSW spot checks
        mov     word [name], n_stosb
        mov     di, buf2 + 1
        mov     cx, 131
        mov     al, 5Ah
        rep     stosb
        inc     word [cases]
        cmp     di, buf2 + 132
        jne     .bad2
        cmp     byte [buf2 + 131], 5Ah
        jne     .bad2
        mov     word [name], n_movsw
        mov     si, buf1 + 1
        mov     di, buf2 + 3
        mov     cx, 65
        rep     movsw
        inc     word [cases]
        cmp     si, buf1 + 131
        jne     .bad2
        mov     ax, [buf1 + 129]
        cmp     ax, [buf2 + 131]
        jne     .bad2
        ret
.bad:   call    fail_case
        jmp     .regs
.bad2:  call    fail_case
        ret

; ---- Checks ---------------------------------------------------------------------------
check_di_cx_zf:
        pushf
        mov     [got_di], di
        mov     [got_cx], cx
        mov     word [got_si], 0
        mov     word [exp_si], 0
        jmp     check_common
check_si_di_cx_zf:
        pushf
        mov     [got_di], di
        mov     [got_cx], cx
        mov     [got_si], si
check_common:
        pop     ax
        and     ax, 40h                 ; ZF
        shr     ax, 6
        mov     [got_zf], al
        inc     word [cases]
        mov     ax, [got_di]
        cmp     ax, [exp_di]
        jne     .bad
        mov     ax, [got_cx]
        cmp     ax, [exp_cx]
        jne     .bad
        mov     ax, [got_si]
        cmp     ax, [exp_si]
        jne     .bad
        cmp     byte [exp_zf], 2
        je      .ok
        mov     al, [got_zf]
        cmp     al, [exp_zf]
        jne     .bad
.ok:    ret
.bad:   call    fail_case
        ret

; print "name n=bp pos=dx align=bx: SI/DI/CX/ZF got .. expected .."
fail_case:
        pusha
        inc     word [fails]
        cmp     word [fails], 12
        ja      .quiet
        mov     dx, [name]
        call    puts
        mov     dx, t_n
        call    puts
        mov     ax, bp
        call    putdec
        mov     dx, t_p
        call    puts
        popa
        pusha
        mov     ax, dx
        call    putdec
        mov     dx, t_a
        call    puts
        mov     ax, bx
        call    putdec
        mov     dx, t_got
        call    puts
        mov     ax, [got_si]
        call    puthex
        mov     dl, '/'
        call    putc
        mov     ax, [got_di]
        call    puthex
        mov     dl, '/'
        call    putc
        mov     ax, [got_cx]
        call    puthex
        mov     dl, '/'
        call    putc
        mov     al, [got_zf]
        xor     ah, ah
        call    putdec
        mov     dx, t_exp
        call    puts
        mov     ax, [exp_si]
        call    puthex
        mov     dl, '/'
        call    putc
        mov     ax, [exp_di]
        call    puthex
        mov     dl, '/'
        call    putc
        mov     ax, [exp_cx]
        call    puthex
        mov     dl, '/'
        call    putc
        mov     al, [exp_zf]
        xor     ah, ah
        call    putdec
        mov     dx, crlf
        call    puts
.quiet: popa
        ret

; ---- Output -------------------------------------------------------------------------
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
puthex: pusha
        mov     cx, 4
.d:     rol     ax, 4
        mov     dl, al
        and     dl, 0Fh
        add     dl, '0'
        cmp     dl, '9'
        jbe     .p
        add     dl, 7
.p:     call    putc
        loop    .d
        popa
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

title   db 'STRTEST (PC98-486 CPU string instructions)', 13, 10, '$'
n_repne db 'REPNE SCASB$'
n_repe  db 'REPE SCASB$'
n_cmps  db 'REPE CMPSB$'
n_movs  db 'REP MOVSB regs$'
n_movsdata db 'REP MOVSB data$'
n_stdscas db 'STD REPNE SCASB$'
n_stdmovs db 'STD REP MOVSB$'
n_lods  db 'LODSB/STOSB loop$'
n_stosb db 'REP STOSB$'
n_movsw db 'REP MOVSW$'
t_n     db ' n=$'
t_p     db ' pos=$'
t_a     db ' align=$'
t_got   db ': got SI/DI/CX/ZF $'
t_exp   db ' exp $'
t_cases db 'Cases $'
t_fails db ', failures $'
t_pass  db 'STRTEST PASS', 13, 10, '$'
t_fail  db 'STRTEST FAIL', 13, 10, '$'
crlf    db 13, 10, '$'
cases   dw 0
fails   dw 0
name    dw 0
exp_si  dw 0
exp_di  dw 0
exp_cx  dw 0
exp_zf  db 0
got_si  dw 0
got_di  dw 0
got_cx  dw 0
got_zf  db 0
align 16
buf1    times MAXLEN + 32 db 0
buf2    times MAXLEN + 48 db 0
