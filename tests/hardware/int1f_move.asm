; SPDX-License-Identifier: GPL-3.0-or-later
; INT 1Fh AH=90h (block move) from the core's resident disk-ROM code
; (software/pc98_ide_resident.asm): install it at D800:0, then move
; conventional -> 200000h -> conventional and compare, check CF and A20.
; Loaded at 1000:0100; RESIDENT is the assembled resident binary.
        cpu     486
        org     100h
bits 16
start:  cli
        cld
        mov     ax, cs
        mov     ds, ax
        mov     ss, ax
        mov     sp, 0FFF0h
        mov     ax, 0D800h              ; install the resident code
        mov     es, ax
        xor     di, di
        mov     si, resident
        mov     cx, resident_end - resident
        rep     movsb
        ; hook INT 1Fh as the resident initializer does (no IDE drive here)
        mov     ax, [es:8]
        xor     dx, dx
        mov     es, dx
        mov     dword [es:1fh*4 + 0], 0         ; previous vector: unused here
        mov     [es:1fh*4], ax
        mov     word [es:1fh*4+2], 0D800h
        mov     ax, 0D800h
        mov     es, ax
        ; pattern in src (conventional, 1000:2000)
        push    cs
        pop     es
        mov     di, src
        mov     cx, 1234
        xor     al, al
.fill:  stosb
        add     al, 37
        loop    .fill
        ; move 1234 bytes: 10000h+src -> 200000h
        mov     word [desc + 10h], 0FFFFh
        mov     dword [desc + 12h], 10000h
        mov     byte [desc + 15h], 93h
        mov     word [desc + 18h], 0FFFFh
        mov     dword [desc + 1ah], 200000h
        mov     byte [desc + 1dh], 93h
        mov     si, src
        mov     di, 0
        mov     cx, 1234
        mov     bx, desc
        mov     ah, 90h
        int     1fh
        mov     ebp, 2
        jc      fail
        ; and back: 200000h -> 10000h+dst
        mov     dword [desc + 12h], 200000h
        mov     byte [desc + 15h], 93h
        mov     dword [desc + 1ah], 10000h
        mov     byte [desc + 1dh], 93h
        xor     si, si
        mov     di, dst
        mov     cx, 1234
        mov     ah, 90h
        int     1fh
        mov     ebp, 3
        jc      fail
        mov     si, src
        mov     di, dst
        mov     cx, 1234
        mov     ebp, 4
        repe    cmpsb
        jne     fail
        ; the destination must not have leaked below 1 MB (A20 off -> 000000h)
        mov     ebp, 5
        xor     ax, ax
        mov     es, ax
        cmp     word [es:0], 0
        jne     fail
        ; limit violation -> CF
        mov     word [desc + 18h], 100
        mov     si, src
        mov     di, 50
        mov     cx, 60
        mov     ah, 90h
        int     1fh
        mov     ebp, 6
        jnc     fail
        ; other functions chain to the previous vector (an IRET stub here)
        mov     ax, 600Dh
        mov     dx, 7FF0h
        out     dx, ax
        hlt
        jmp     $
fail:   mov     dx, 7FE4h
        out     dx, ax
        mov     ax, 0DEADh
        mov     dx, 7FF0h
        out     dx, ax
        hlt
        jmp     $
align 16
desc:   times 30h db 0
src:    times 1300 db 0
dst:    times 1300 db 0
resident:
        incbin  RESIDENT
resident_end:
