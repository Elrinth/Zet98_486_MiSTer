; SPDX-License-Identifier: GPL-3.0-or-later
bits 16
org 0x1000
start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x9000
    cmp byte [0x2300], 1
    je second_boot

    ; Actual 486-only instruction, unaligned DWORD memory and PC-98 I/O lanes.
    mov eax, 0x12345678
    bswap eax
    mov [0x2003], eax
    xor eax, eax
    mov eax, [0x2003]
    cmp eax, 0x78563412
    jne fail
    mov dx, 0x0189
    out dx, eax
    xor eax, eax
    in eax, dx
    cmp eax, 0x78563412
    jne fail
    mov dword [0x200f], 0x91827364
    mov si, 0x2003
    mov di, 0x2101
    mov cx, 4
    cld
    rep movsd
    cmp dword [0x2101], 0x78563412
    jne fail
    cmp dword [0x210d], 0x91827364
    jne fail

    ; A20 disabled at reset; enabling it must not wrap unavailable high RAM.
    mov byte [1], 0xa5
    mov ax, 0xffff
    mov es, ax
    cmp byte [es:0x11], 0xa5
    jne fail
    mov dx, 0x00f2
    out dx, al
    in al, dx
    cmp al, 0xfe
    jne fail
    mov byte [es:0x11], 0x5a
    cmp byte [es:0x11], 0xff
    jne fail
    cmp byte [1], 0xa5
    jne fail
    mov dx, 0x00f6
    mov al, 3
    out dx, al
    in al, dx
    cmp al, 1
    jne fail
    cmp byte [es:0x11], 0xa5
    jne fail
    xor ax, ax
    mov es, ax

    ; The test PIC provides its vector only during interrupt_done, like INTA.
    mov word [0x80*4], handler
    mov word [0x80*4+2], 0
    mov dx, 0x7ff0
    mov ax, 0x0011
    out dx, ax
    sti
    hlt
    cli
    cmp word [0x2200], 0xcafe
    jne fail

    ; Software CPU reset must preserve RAM and clear A20.
    mov byte [0x2300], 1
    mov dx, 0x00f2
    out dx, al
    mov dx, 0x00f0
    out dx, al
    jmp fail

second_boot:
    mov dx, 0x00f2
    in al, dx
    cmp al, 0xff
    jne fail
    cmp dword [0x210d], 0x91827364
    jne fail
    mov dx, 0x7ff0
    mov ax, 0x600d
    out dx, ax
    hlt
    jmp $

handler:
    mov word [0x2200], 0xcafe
    iret

fail:
    mov dx, 0x7ff0
    mov ax, 0xdead
    out dx, ax
    cli
    hlt
    jmp $
