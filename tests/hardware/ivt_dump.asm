; SPDX-License-Identifier: GPL-3.0-or-later
; IVTDUMP.COM [first-hex-digit]: print interrupt vectors as SSSS:OOOO, four
; per line, then the PIC masks (M= master, S= slave); with an argument 0-F only that block of 16 vectors (x0h-xFh),
; otherwise vectors 00h-FFh. For comparing BIOSes at the DOS prompt.
        cpu     8086
        org     100h
start:  xor     bx, bx                  ; first vector
        mov     cx, 256                 ; count
        mov     si, 81h
.arg:   lodsb
        cmp     al, ' '
        je      .arg
        cmp     al, 13
        je      .go
        call    hexval
        jc      .go
        mov     bl, al
        mov     cl, 4
        shl     bx, cl                  ; block * 16
        mov     cx, 16
.go:    push    ds
        xor     ax, ax
        mov     es, ax
        pop     ds
.line:  mov     al, bl
        call    phexb
        mov     dl, ':'
        call    putc
        push    cx
        mov     cx, 4
.vec:   mov     dl, ' '
        call    putc
        mov     di, bx
        shl     di, 1
        shl     di, 1
        mov     ax, [es:di+2]
        call    phexw
        mov     dl, ':'
        call    putc
        mov     ax, [es:di]
        call    phexw
        inc     bx
        loop    .vec
        pop     cx
        mov     dl, 13
        call    putc
        mov     dl, 10
        call    putc
        sub     cx, 4
        ja      .line
        mov     dl, 'M'
        call    putc
        in      al, 02h
        call    phexb
        mov     dl, ' '
        call    putc
        mov     dl, 'S'
        call    putc
        in      al, 0Ah
        call    phexb
        mov     dl, 13
        call    putc
        mov     dl, 10
        call    putc
        mov     ax, 4C00h
        int     21h

hexval: cmp     al, '0'
        jb      .bad
        cmp     al, '9'
        jbe     .num
        and     al, 0DFh
        cmp     al, 'A'
        jb      .bad
        cmp     al, 'F'
        ja      .bad
        sub     al, 7
.num:   sub     al, '0'
        clc
        ret
.bad:   stc
        ret

putc:   push    ax
        mov     ah, 2
        int     21h
        pop     ax
        ret
phexw:  push    ax
        mov     al, ah
        call    phexb
        pop     ax
phexb:  push    ax
        push    cx
        mov     cl, 4
        shr     al, cl
        pop     cx
        call    .nib
        pop     ax
.nib:   push    ax
        and     al, 0Fh
        add     al, '0'
        cmp     al, '9'
        jbe     .p
        add     al, 7
.p:     mov     dl, al
        call    putc
        pop     ax
        ret
