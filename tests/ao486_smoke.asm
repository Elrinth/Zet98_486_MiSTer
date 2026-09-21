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

%ifdef REP_COUNT_TESTS
    ; 16-bit REP uses CX even with nonzero ECX high bits. Partial CL/CH
    ; writes must update the count predicates on the same edge as ECX.
    mov dword [0x2400], 0x11223344
    mov dword [0x2410], 0xa5a5a5a5
    mov esi, 0x2400
    mov edi, 0x2410
    mov ecx, 0x12340000
    rep movsb
    cmp edi, 0x2410
    jne fail
    cmp ecx, 0x12340000
    jne fail
    mov cl, 1
    rep movsb
    cmp ecx, 0x12340000
    jne fail
    cmp dword [0x2410], 0xa5a5a544
    jne fail
    mov cx, 0x0101
    mov ch, 0
    mov al, 0x5a
    rep stosb
    cmp ecx, 0x12340000
    jne fail
    cmp dword [0x2410], 0xa5a55a44
    jne fail

    ; ECX=10000h is not zero for 32-bit-address REP. End on the first
    ; mismatch rather than performing 65536 iterations in the simulator.
    mov byte [0x2410], 0xff
    mov esi, 0x2400
    mov edi, 0x2410
    mov ecx, 0x10000
    a32 repe cmpsb
    cmp ecx, 0xffff
    jne fail
    cmp edi, 0x2411
    jne fail

    ; ECX=10001h is not one: continue past the first equal byte and stop
    ; on the second unequal byte. This also crosses the low-word boundary.
    mov byte [0x2410], 0x44
    mov esi, 0x2400
    mov edi, 0x2410
    mov ecx, 0x10001
    a32 repe cmpsb
    cmp ecx, 0xffff
    jne fail
    cmp esi, 0x2402
    jne fail
    cmp edi, 0x2412
    jne fail

    mov edi, 0x2420
    xor ecx, ecx
    mov eax, 0x91827364
    a32 rep stosd
    cmp edi, 0x2420
    jne fail
    inc ecx
    a32 rep stosd
    test ecx, ecx
    jnz fail
    cmp edi, 0x2424
    jne fail
    cmp dword [0x2420], 0x91827364
    jne fail
%endif

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
