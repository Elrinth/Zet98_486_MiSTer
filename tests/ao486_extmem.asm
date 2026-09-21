; SPDX-License-Identifier: GPL-3.0-or-later
; Actual 486 protected-mode access to the optional DDR RAM backend.
bits 16
cpu 486
org 1000h
    cli
    cld
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 9000h
    out 0f2h, al
    lgdt [gdtr]
    mov eax, cr0
    or al, 1
    mov cr0, eax
    jmp 08h:protected
align 8
gdt:
    dq 0
    dq 00cf9a000000ffffh
    dq 00cf92000000ffffh
gdtr:
    dw 23
    dd gdt
bits 32
protected:
    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 9000h
    cmp dword [500h], 098486001h
    je after_reset
    mov dword [500h], 098486001h
    mov esi, 100000h
    call check_location
    mov esi, 1ffffch
    call check_location
    mov esi, 0effff8h
    call check_location
%if TOP_MB = 64
    mov esi, 1000000h
    call check_location
    mov esi, 3fffff8h
    call check_location
%endif
    mov dword [TOP_MB * 100000h], 0deadbeefh
    cmp dword [TOP_MB * 100000h], -1
    jne fail
    mov dword [0f00000h], 0deadbeefh
    cmp dword [0f00000h], -1
    jne fail
    ; Copy through DDR in both directions with a full-DWORD instruction.
    mov edi, 7000h
    mov ecx, 64
fill:
    mov eax, ecx
    xor eax, 0a5967893h
    stosd
    loop fill
    mov esi, 7000h
    mov edi, 180000h
    mov ecx, 64
    rep movsd
    mov esi, 180000h
    mov edi, 8000h
    mov ecx, 64
    rep movsd
    mov esi, 7000h
    mov edi, 8000h
    mov ecx, 64
    repe cmpsd
    jne fail
    ; Fetch and execute code from DDR, including the complete fetch burst.
    mov dword [200000h], 00df00db8h
    mov dword [200004h], 00000c360h
    mov eax, 200000h
    call eax
    cmp eax, 600df00dh
    jne fail
    mov dword [400000h], 098486064h
    xor eax, eax
    out 0f0h, al
    jmp $
after_reset:
    cmp dword [400000h], 098486064h
    jne fail
    mov ax, 600dh
    jmp report
check_location:
    mov dword [esi], 12345678h
    mov byte [esi+1], 0abh
    cmp dword [esi], 1234ab78h
    jne fail
    mov word [esi+2], 0cdefh
    cmp dword [esi], 0cdefab78h
    jne fail
    mov dword [esi+3], 10203040h
    cmp dword [esi+3], 10203040h
    jne fail
    ret
fail:
    mov ax, 0deadh
report:
    mov dx, 7ff0h
    out dx, ax
    hlt
    jmp $
