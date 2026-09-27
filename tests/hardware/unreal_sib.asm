; SPDX-License-Identifier: GPL-3.0-or-later
; Unreal-mode (real mode, 4 GB data limits) stores to extended memory with the
; 32-bit addressing forms EMM386.EXE (MS-DOS 5, NEC) uses to build its page
; tables: SIB with no base, scaled index, base+index*scale+disp, FS/ES/GS
; overrides. Each value is read back from protected mode through a flat
; selector. Loaded at 1000:0100; reports 600Dh to port 7FF0h, or EBP = case.
        cpu     486
        org     100h
LIN     equ     10000h
bits 16
start:  cli
        cld
        mov     ax, cs
        mov     ds, ax
        mov     ss, ax
        mov     sp, 0FFF0h
        xor     al, al
        out     0F2h, al                ; A20 on
        ; unreal mode: load 4 GB limits in a short protected-mode trip
        lgdt    [gdtr]
        mov     eax, cr0
        or      al, 1
        mov     cr0, eax
        jmp     8:.pm
.pm:    mov     ax, 10h
        mov     ds, ax
        mov     es, ax
        mov     fs, ax
        mov     gs, ax
        mov     eax, cr0
        and     al, 0FEh
        mov     cr0, eax
        jmp     1000h:.rm
.rm:    xor     ax, ax                  ; bases 0, limits stay 4 GB
        mov     es, ax
        mov     fs, ax
        mov     gs, ax
        mov     ax, cs
        mov     ds, ax
        ; the store forms
        mov     edi, 120000h / 4
        mov     eax, 11111111h
        mov     dword [fs:edi*4], eax           ; 120000 (no base, index*4)
        inc     edi
        mov     eax, 22222222h
        mov     dword [fs:edi*4], eax           ; 120004
        mov     ebx, 120100h
        mov     esi, 3
        mov     eax, 33333333h
        mov     dword [es:ebx + esi*8 + 10h], eax   ; 120128
        mov     ecx, 44444444h
        mov     dword [es:ebx + esi*8 + 14h], ecx   ; 12012C
        mov     edx, 55555555h
        mov     dword [es:ebx + esi*4 + 10h], edx   ; 12011C
        mov     esi, 120200h / 8
        mov     dword [es:esi*8], 66666666h     ; 120200 (imm, no base, index*8)
        mov     dword [es:esi*8 + 4], 77777777h ; 120204
        mov     edi, 120300h
        mov     eax, 88888888h
        mov     dword [es:edi], eax             ; 120300
        mov     eax, 99999999h
        a32 stosd                               ; 120300 again, EDI -> 120304
        mov     eax, 0BBBBBBBBh
        a32 stosd                               ; 120304
        mov     edi, 120400h
        mov     esi, 2
        mov     ebx, 0AAAAAAAAh
        mov     dword [gs:esi + edi*8 - 120400h*7], ebx ; 120402 (unaligned)
        ; read the same forms back in unreal mode
        mov     edi, 120000h / 4
        mov     ebp, 1
        cmp     dword [fs:edi*4], 11111111h
        jne     rm_bad
        ; protected mode: check every value through a flat selector
        mov     eax, cr0
        or      al, 1
        mov     cr0, eax
        jmp     dword 18h:(LIN + check32)
rm_bad: mov     dx, 7FE4h
        out     dx, ax
        mov     ax, 0DEADh
        mov     dx, 7FF0h
        out     dx, ax
        hlt
        jmp     $
bits 32
check32:
        mov     ax, 10h
        mov     ds, ax
%macro CHK 3
        mov     ebp, %1
        mov     eax, [%2]
        cmp     eax, %3
        jne     bad32
%endmacro
        CHK     2, 120000h, 11111111h
        CHK     3, 120004h, 22222222h
        CHK     4, 120128h, 33333333h
        CHK     5, 12012Ch, 44444444h
        CHK     6, 12011Ch, 55555555h
        CHK     7, 120200h, 66666666h
        CHK     8, 120204h, 77777777h
        CHK     9, 120300h, 99999999h
        CHK     10, 120304h, 0BBBBBBBBh
        CHK     11, 120402h, 0AAAAAAAAh
        CHK     12, 020000h, 0          ; nothing wrapped below 1 MB
        CHK     13, 020128h, 0
        mov     ax, 600Dh
        mov     dx, 7FF0h
        out     dx, ax
        hlt
        jmp     $
bad32:  mov     ebx, eax
        mov     dx, 7FE4h
        out     dx, ax
        mov     ax, 0DEADh
        mov     dx, 7FF0h
        out     dx, ax
        hlt
        jmp     $
align 8
gdt:    dq      0
        dq      00009A010000FFFFh       ; 08h code16, base 10000h
        dq      00CF92000000FFFFh       ; 10h data, flat 4 GB
        dq      00CF9A000000FFFFh       ; 18h code32, flat
gdtr:   dw      $ - gdt - 1
        dd      LIN + gdt
