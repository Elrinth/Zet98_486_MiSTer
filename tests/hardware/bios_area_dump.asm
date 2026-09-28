; SPDX-License-Identifier: GPL-3.0-or-later
; BIOSAREA.COM hh: hex dump of 0000:hh00-hhFF (one or two hex digits; 4 or 5
; -> BIOS work area 0400h-05FFh), 16 bytes per line, for comparing BIOSes and
; reading resident DOS code at the DOS prompt.
        cpu     8086
        org     100h
start:  mov     si, 81h
.arg:   lodsb
        cmp     al, ' '
        je      .arg
        call    hexval
        mov     bh, al
        lodsb
        call    hexval
        jc      .one
        mov     cl, 4
        shl     bh, cl
        or      bh, al                  ; two digits: BX = hh00h
.one:   xor     bl, bl
        xor     ax, ax
        mov     es, ax
        mov     cx, 16                  ; lines
.line:  mov     ax, bx
        call    phexw
        mov     dl, ':'
        call    putc
        push    cx
        mov     cx, 16
.b:     mov     dl, ' '
        call    putc
        mov     al, [es:bx]
        call    phexb
        inc     bx
        loop    .b
        pop     cx
        mov     dl, 13
        call    putc
        mov     dl, 10
        call    putc
        loop    .line
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
