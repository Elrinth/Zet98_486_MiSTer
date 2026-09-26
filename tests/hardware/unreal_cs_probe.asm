; SPDX-License-Identifier: GPL-3.0-or-later
; CR0 mode changes must preserve visible CS, including its low two bits.
; Entering protected mode still has CPL 0 before the first CS reload.
bits 16
cpu 386
org 1000h
    cli
    cld
    xor ax,ax
    mov ds,ax
    mov ss,ax
    mov sp,9000h
    lgdt [gdtr]
    mov cx,40h
next_segment:
    mov [entry+2],cx
    mov ax,cx
    shl ax,4
    mov bx,bounce
    sub bx,ax
    mov [entry],bx
    call far [entry]
    inc cx
    cmp cx,44h
    jb next_segment
    ; A real protected-mode far transfer establishes the new selector.
    mov word [entry+2],43h
    mov word [entry],far_bounce-430h
    jmp far [entry]
far_bounce:
    mov eax,cr0
    or al,1
    mov cr0,eax
    jmp 08h:protected_target
protected_target:
    mov bx,cs
    cmp bx,8
    jne fail
    mov eax,cr0
    and al,0feh
    mov cr0,eax
    jmp 0:finished
finished:
    mov ax,600dh
    jmp report
bounce:
    mov bx,cs
    cmp bx,cx
    jne fail
    mov eax,cr0
    or al,1
    mov cr0,eax
    jmp short .in_protected
.in_protected:
    push cs
    pop bx
    cmp bx,cx
    jne fail
    ; Both accesses require CPL 0 despite the unchanged visible CS bits.
    mov ebx,cr0
    mov dx,10h
    mov ds,dx
    mov es,dx
    and al,0feh
    mov cr0,eax
    xor dx,dx
    mov ds,dx
    mov es,dx
    push cs
    pop bx
    cmp bx,cx
    jne fail
    retf
fail:
    mov ax,0deadh
report:
    mov dx,7ff0h
    out dx,ax
    hlt
    jmp $
entry: dd 0
align 8
gdt:
    dq 0
    dq 00009a000000ffffh
    dq 00cf92000000ffffh
gdtr:
    dw 23
    dd gdt
