; SPDX-License-Identifier: GPL-3.0-or-later
; Destructive EXTENDED-memory probe for a disposable DOS boot disk only.
; No XMS/EMS manager or resident application may own extended RAM for this test.
; Assembles with -DTOP_MB=16 or 64. Never tests ROM/VRAM or the 15-16 MB hole.
bits 16
cpu 486
org 100h
%ifndef TOP_MB
%define TOP_MB 16
%endif
%if TOP_MB != 16 && TOP_MB != 64
%error TOP_MB must be 16 or 64
%endif
start:
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0fffeh
    cld
    mov [real_jump+3], ax
    movzx eax, ax
    shl eax, 4
    mov [code_desc+2], ax
    mov [data_desc+2], ax
    mov edx, eax
    shr edx, 16
    mov [code_desc+4], dl
    mov [data_desc+4], dl
    add eax, gdt
    mov [gdtr+2], eax
    in al, 0f2h
    and al, 1
    mov [old_a20], al
    out 0f2h, al
    mov eax, cr0
    mov [old_cr0], eax
    or al, 1
    lgdt [gdtr]
    mov cr0, eax
    jmp 08h:protected

protected:
    mov ax, 10h
    mov ds, ax
    mov ss, ax
    mov ax, 18h
    mov es, ax
    ; Write independent sentinels across every mapped megabyte first, then
    ; verify them all. A truncated address decoder cannot pass by aliasing.
    mov ebx, 1
.fill:
    call addresses
    mov eax, edi
    xor eax, 5a98c36dh
    mov [es:edi], eax
    not eax
    mov [es:esi], eax
    call next_mb
    jb .fill
    mov ebx, 1
.verify:
    call addresses
    mov eax, edi
    xor eax, 5a98c36dh
    cmp [es:edi], eax
    jne failed
    not eax
    cmp [es:esi], eax
    jne failed
    call next_mb
    jb .verify
    mov edi, 100200h
    mov dword [es:edi], 12345678h
    mov byte [es:edi+1], 0abh
    mov word [es:edi+2], 0cdefh
    cmp dword [es:edi], 0cdefab78h
    jne failed
    mov dword [es:edi+3], 10203040h
    cmp dword [es:edi+3], 10203040h
    jne failed
    ; Reserved and absent memory must not alias a tested sentinel.
    mov edi, 0f00000h
    cmp dword [es:edi], -1
    jne failed
    mov edi, TOP_MB*100000h
    cmp dword [es:edi], -1
    jne failed
    mov byte [result], 1
    jmp leave_protected
failed:
    mov [failed_address], edi
leave_protected:
    ; Reload a real-mode-sized segment before clearing PE. Code/data/stack
    ; descriptors share the COM segment base, so no low-memory trampoline.
    mov ax, 10h
    mov es, ax
    mov eax, [old_cr0]
    mov cr0, eax
real_jump:
    jmp 0:real_mode
real_mode:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov al, [old_a20]
    add al, 2
    out 0f6h, al
%ifdef SIM
    cmp byte [result], 1
    mov ax, 600dh
    je .report
    mov ax, 0deadh
.report:
    mov dx, 7ff0h
    out dx, ax
    hlt
    jmp $
%else
    sti
    mov dx, critical_error
    mov ax, 2524h
    int 21h
    mov si, fail_text
    cmp byte [result], 1
    jne .text
    mov si, pass_text
.text:
    mov [message], si
    xor cx, cx
.print:
    lodsb
    test al, al
    jz .save
    push cx
    push si
    mov dl, al
    mov ah, 2
    int 21h
    pop si
    pop cx
    inc cx
    jmp .print
.save:
    mov [length], cx
    mov dx, log_name
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc save_error
    mov bx, ax
    mov dx, [message]
    mov cx, [length]
    mov ah, 40h
    int 21h
    jc save_error
    cmp ax, [length]
    jne save_error
    mov ah, 3eh
    int 21h
    jc save_error
    mov ah, 0dh
    int 21h
    jmp halt
save_error:
    mov dx, save_failed
    mov ah, 9
    int 21h
halt:
    sti
    hlt
    jmp halt
critical_error:
    mov al, 3
    iret
%endif
addresses:
    mov edi, ebx
    shl edi, 20
    mov esi, edi
    add esi, 0ffff8h
    add edi, 100h
    ret
next_mb:
    inc ebx
    cmp ebx, 15
    jne .limit
    inc ebx
.limit:
    cmp ebx, TOP_MB
    ret
align 8
gdt:
    dq 0
code_desc: dq 00009a000000ffffh
data_desc: dq 000092000000ffffh
    dq 00cf92000000ffffh
gdtr: dw 31
    dd 0
old_cr0: dd 0
old_a20: db 0
result: db 0
failed_address: dd 0
message: dw 0
length: dw 0
log_name: db 'Z98RAM.TXT',0
%if TOP_MB = 16
pass_text: db 13,10,'PASS: 16 MB physical map (14 MB extended RAM).',13,10
%else
pass_text: db 13,10,'PASS: 64 MB physical map (62 MB extended RAM).',13,10
%endif
    db 'Independent sentinels at both ends of every mapped MB;',13,10
    db 'byte/word/unaligned DWORD checks and real-mode return passed.',13,10
    db 'This is not an XMS/BIOS memory-discovery test.',13,10,0
fail_text: db 13,10,'FAIL: extended RAM mapping/data check.',13,10,0
save_failed: db 13,10,'ERROR saving Z98RAM.TXT',13,10,'$'
times 0 * (1 / (($ - $$) <= 2011)) db 0
