; SPDX-License-Identifier: GPL-3.0-or-later
; MEMTEST.COM [passes]: memory stress test for qualifying core builds.
; Conventional RAM (every free 64 KB block above this program) gets, per pass:
;   1. REP STOSW bursts with 0000/FFFF/AAAA/5555/pass-dependent words, REPE SCASW
;   2. address-dependent words (offset XOR segment XOR pass), checked afterwards
;   3. store-then-load interleave: each word is read back right after its store,
;      and the previous word is re-read (exercises posted-write ordering)
;   4. even bytes then odd bytes written separately (byte enables), then words
;   5. REP MOVSW of the block's first half onto its second half, compared
; Extended RAM through XMS (needs HIMEM.SYS): up to 16 MB is allocated and filled
; in 16 KB chunks via XMS moves with chunk-dependent patterns, then moved back
; and compared.
; Prints each pass and the first errors (address, expected, got). Exit code =
; 1 if any error. Default 3 passes; "MEMTEST 20" runs 20.
        cpu     386
        org     100h
bits 16
CHUNK   equ     16384                  ; XMS move size in bytes

start:  cld
        mov     dx, title
        call    puts
        ; passes from the command line (decimal), default 3
        mov     si, 81h
        xor     ax, ax
.arg:   mov     bl, [si]
        inc     si
        cmp     bl, ' '
        je      .arg
        sub     bl, '0'
        cmp     bl, 9
        ja      .argdone
.digit: imul    ax, 10
        xor     bh, bh
        add     ax, bx
        mov     bl, [si]
        inc     si
        sub     bl, '0'
        cmp     bl, 9
        jbe     .digit
.argdone:
        test    ax, ax
        jnz     .havepasses
        mov     ax, 3
.havepasses:
        mov     [passes], ax
        ; conventional range: 64 KB above this program up to the top of memory
        mov     ax, cs
        add     ax, 1000h
        mov     [cseg0], ax
        mov     ax, [2]                ; PSP: first paragraph after our block
        sub     ax, 80h                ; keep 2 KB spare
        mov     [ctop], ax
        call    xms_init

.pass:  inc     word [passno]
        mov     dx, t_pass
        call    puts
        mov     ax, [passno]
        call    putdec
        mov     dx, t_conv
        call    puts
        call    conv_test
        mov     ax, [convkb]
        call    putdec
        mov     dx, t_kb
        call    puts
        cmp     word [xmskb], 0
        je      .noxms
        mov     dx, t_xms
        call    puts
        call    xms_test
        mov     ax, [xmskb]
        call    putdec
        mov     dx, t_kb
        call    puts
.noxms: mov     dx, t_errs
        call    puts
        mov     ax, [errors]
        call    putdec
        mov     dx, crlf
        call    puts
        mov     ax, [passno]
        cmp     ax, [passes]
        jb      .pass

        call    xms_free
        mov     dx, t_ok
        mov     al, 0
        cmp     word [errors], 0
        je      .final
        mov     dx, t_fail
        mov     al, 1
.final: push    ax
        call    puts
        pop     ax
        mov     ah, 4Ch
        int     21h

; ---- Conventional memory ------------------------------------------------------
conv_test:
        mov     word [convkb], 0
        mov     ax, [cseg0]
.block: mov     [curseg], ax
        mov     cx, [ctop]
        sub     cx, ax                 ; paragraphs left
        jbe     .done
        cmp     cx, 1000h
        jbe     .size
        mov     cx, 1000h
.size:  shl     cx, 3                  ; words in this block (paragraphs * 8)
        jnz     .ok
        mov     cx, 8000h              ; a full 64 KB is 32768 words
.ok:    mov     [words], cx
        mov     es, [curseg]
        ; 1. bursts
        mov     si, fills
.fill:  lodsw
        cmp     si, fills_end + 2
        ja      .addr
        cmp     si, fills_end
        jbe     .usefill
        mov     ax, [passno]           ; last fill word depends on the pass
        imul    ax, 3D5Bh
.usefill:
        call    burst
        jmp     .fill
        ; 2. address-dependent words
.addr:  call    addr_pattern
        ; 3. store/load interleave
        call    interleave
        ; 4. byte enables
        call    bytes
        ; 5. copies
        call    copies
        mov     ax, [words]
        shr     ax, 9                  ; words -> KB
        add     [convkb], ax
        mov     ax, [curseg]
        add     ax, 1000h
        jmp     .block
.done:  ret

; fill ES:0 with AX via REP STOSW, then REPE SCASW
burst:  xor     di, di
        mov     cx, [words]
        rep     stosw
        xor     di, di
        mov     cx, [words]
.scan:  repe    scasw
        je      .done
        push    ax
        push    cx
        mov     bx, [es:di-2]
        sub     di, 2
        call    report_error            ; ES:DI expected AX got BX
        add     di, 2
        pop     cx
        pop     ax
        jcxz    .done
        jmp     .scan
.done:  ret

addr_pattern:
        xor     di, di
        mov     cx, [words]
        mov     dx, [curseg]
        xor     dx, [passno]
.w:     mov     ax, di
        xor     ax, dx
        stosw
        loop    .w
        xor     di, di
        mov     cx, [words]
.r:     mov     ax, di
        xor     ax, dx
        mov     bx, [es:di]
        cmp     ax, bx
        je      .n
        call    report_error
.n:     add     di, 2
        loop    .r
        ret

interleave:
        xor     di, di
        mov     cx, [words]
        mov     dx, [passno]
        rol     dx, 5
        xor     dx, 0A5C3h
.w:     mov     ax, di
        add     ax, dx
        not     ax
        mov     [es:di], ax
        mov     bx, [es:di]             ; load right after the store
        cmp     ax, bx
        je      .prev
        call    report_error
.prev:  test    di, di
        jz      .n
        mov     ax, di
        sub     ax, 2
        add     ax, dx
        not     ax
        mov     bx, [es:di-2]           ; the previous word must still be intact
        cmp     ax, bx
        je      .n
        sub     di, 2
        call    report_error
        add     di, 2
.n:     add     di, 2
        loop    .w
        ret

bytes:  xor     di, di
        mov     cx, [words]
        mov     dl, [passno]
.even:  mov     al, dl
        xor     al, 5Ah
        add     al, cl
        mov     [es:di], al
        add     di, 2
        loop    .even
        mov     di, 1
        mov     cx, [words]
.odd:   mov     al, dl
        xor     al, 0C3h
        sub     al, cl
        mov     [es:di], al
        add     di, 2
        loop    .odd
        xor     di, di
        mov     cx, [words]
.chk:   mov     al, dl
        xor     al, 5Ah
        add     al, cl
        mov     ah, dl
        xor     ah, 0C3h
        sub     ah, cl
        mov     bx, [es:di]
        cmp     ax, bx
        je      .n
        call    report_error
.n:     add     di, 2
        loop    .chk
        ret

copies: mov     cx, [words]
        shr     cx, 1                   ; half the block
        jz      .done
        ; first half: address pattern with a different seed
        xor     di, di
        mov     dx, [passno]
        xor     dx, 6B2Dh
        push    cx
.w:     mov     ax, di
        rol     ax, 3
        xor     ax, dx
        stosw
        loop    .w
        pop     cx
        push    ds
        push    es
        pop     ds
        xor     si, si
        mov     di, cx
        shl     di, 1                   ; destination: second half
        push    cx
        rep     movsw
        pop     cx
        pop     ds
        xor     si, si
        mov     di, cx
        shl     di, 1
.c:     mov     ax, si
        rol     ax, 3
        xor     ax, dx
        mov     bx, [es:di]
        cmp     ax, bx
        je      .n
        call    report_error
.n:     add     si, 2
        add     di, 2
        loop    .c
.done:  ret

; ---- XMS ----------------------------------------------------------------------
xms_init:
        mov     ax, 4300h
        int     2Fh
        cmp     al, 80h
        jne     .none
        mov     ax, 4310h
        int     2Fh
        mov     [xmsentry], bx
        mov     [xmsentry+2], es
        push    ds
        pop     es
        mov     ah, 08h                 ; largest free block in KB -> AX
        call    far [xmsentry]
        cmp     ax, 64
        jb      .none
        cmp     ax, 16384
        jbe     .alloc
        mov     ax, 16384
.alloc: and     ax, 0FFF0h              ; whole 16 KB chunks
        mov     dx, ax
        mov     [xmskb], ax
        mov     ah, 09h
        call    far [xmsentry]
        test    ax, ax
        jz      .none
        mov     [xmshandle], dx
        ret
.none:  mov     word [xmskb], 0
        mov     dx, t_noxms
        call    puts
        ret

xms_free:
        cmp     word [xmskb], 0
        je      .done
        mov     dx, [xmshandle]
        mov     ah, 0Ah
        call    far [xmsentry]
.done:  ret

; fill bufA with the pattern for chunk BX (pass-dependent)
chunk_pattern:
        push    ds
        pop     es
        mov     di, bufA
        mov     cx, CHUNK/2
        mov     dx, bx
        imul    dx, 7919
        xor     dx, [passno]
.p:     mov     ax, di
        add     ax, dx
        rol     ax, 1
        stosw
        loop    .p
        ret

xms_test:
        mov     cx, [xmskb]
        shr     cx, 4                   ; 16 KB chunks
        xor     bx, bx
.put:   push    cx
        push    bx
        call    chunk_pattern
        pop     bx
        push    bx
        ; move bufA (handle 0 = conventional DS:bufA) -> EMB offset bx*CHUNK
        mov     dword [mv_len], CHUNK
        mov     word [mv_srch], 0
        mov     word [mv_srco], bufA
        mov     [mv_srco+2], ds
        mov     ax, [xmshandle]
        mov     [mv_dsth], ax
        movzx   eax, bx
        imul    eax, CHUNK
        mov     [mv_dsto], eax
        mov     si, movestruct
        mov     ah, 0Bh
        call    far [xmsentry]
        test    ax, ax
        jnz     .putok
        inc     word [errors]
.putok: pop     bx
        pop     cx
        inc     bx
        loop    .put

        mov     cx, [xmskb]
        shr     cx, 4
        xor     bx, bx
.get:   push    cx
        push    bx
        mov     dword [mv_len], CHUNK
        mov     ax, [xmshandle]
        mov     [mv_srch], ax
        movzx   eax, bx
        imul    eax, CHUNK
        mov     [mv_srco], eax
        mov     word [mv_dsth], 0
        mov     word [mv_dsto], bufB
        mov     [mv_dsto+2], ds
        mov     si, movestruct
        mov     ah, 0Bh
        call    far [xmsentry]
        test    ax, ax
        jnz     .getok
        inc     word [errors]
.getok: pop     bx
        push    bx
        call    chunk_pattern           ; expected data back in bufA
        mov     si, bufA
        mov     di, bufB
        mov     cx, CHUNK/2
.cmp:   repe    cmpsw
        je      .chunkok
        ; report: "XMS" offset (chunk, word) expected [si-2] got [di-2]
        push    cx
        push    si
        push    di
        mov     ax, [si-2]
        mov     dx, [di-2]
        call    report_xms
        pop     di
        pop     si
        pop     cx
        jcxz    .chunkok
        jmp     .cmp
.chunkok:
        pop     bx
        pop     cx
        inc     bx
        loop    .get
        ret

; ---- Error reporting ------------------------------------------------------------
; ES:DI = address, AX = expected, BX = got. Preserves registers.
report_error:
        pusha
        push    es
        inc     word [errors]
        cmp     word [errors], 8
        ja      .quiet
        push    ax
        push    bx
        mov     dx, t_err
        call    puts
        mov     ax, es
        call    puthex
        mov     dl, ':'
        call    putc
        mov     ax, di
        call    puthex
        mov     dx, t_exp
        call    puts
        pop     bx
        pop     ax
        push    bx
        call    puthex
        mov     dx, t_got
        call    puts
        pop     ax
        call    puthex
        mov     dx, crlf
        call    puts
.quiet: pop     es
        popa
        ret

; BX = chunk, AX = expected, DX = got, SI = bufA pointer after the mismatch
report_xms:
        pusha
        inc     word [errors]
        cmp     word [errors], 8
        ja      .quiet
        push    dx
        push    ax
        push    si
        mov     dx, t_xerr
        call    puts
        mov     ax, bx
        call    puthex
        mov     dl, '+'
        call    putc
        pop     ax
        sub     ax, bufA + 2
        call    puthex
        mov     dx, t_exp
        call    puts
        pop     ax
        call    puthex
        mov     dx, t_got
        call    puts
        pop     ax
        call    puthex
        mov     dx, crlf
        call    puts
.quiet: popa
        ret

; ---- Output -------------------------------------------------------------------
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

title   db 'MEMTEST (PC98-486 build check)', 13, 10, '$'
t_pass  db 'Pass $'
t_conv  db ': conventional $'
t_xms   db ' KB, XMS $'
t_kb    db ' KB$'
t_errs  db ', errors so far $'
t_err   db '  RAM $'
t_xerr  db '  XMS chunk $'
t_exp   db ' expected $'
t_got   db ' got $'
t_noxms db 'No XMS driver (HIMEM.SYS); testing conventional memory only.', 13, 10, '$'
t_ok    db 'MEMTEST PASS', 13, 10, '$'
t_fail  db 'MEMTEST FAIL', 13, 10, '$'
crlf    db 13, 10, '$'
fills   dw 0000h, 0FFFFh, 0AAAAh, 5555h
fills_end dw 0                          ; placeholder: replaced by the pass-dependent word
passes  dw 3
passno  dw 0
errors  dw 0
convkb  dw 0
xmskb   dw 0
xmshandle dw 0
xmsentry dd 0
cseg0   dw 0
ctop    dw 0
curseg  dw 0
words   dw 0
movestruct:
mv_len  dd 0
mv_srch dw 0
mv_srco dd 0
mv_dsth dw 0
mv_dsto dd 0
align 16
bufA    times CHUNK db 0
bufB    times CHUNK db 0
