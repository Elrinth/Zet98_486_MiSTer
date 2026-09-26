; SPDX-License-Identifier: GPL-3.0-or-later
; Experimental ao486-only CONFIG.SYS initializer, before HIMEMX(98).
; Detect the core's 16/64 MB map, preserve probe words, publish PC-98 BIOS
; memory counts. Not an XMS manager, and not intended for an original PC-98.
bits 16
cpu 486
%ifdef SIM
org 100h
    jmp simulation
%else
org 0
%endif
header:
    dd 0ffffffffh
    dw 8000h
    dw strategy, interrupt
    db 'Z98MEM  '
request: dd 0
strategy:
    mov [cs:request], bx
    mov [cs:request+2], es
    retf
interrupt:
    pushf
    pushad
    push ds
    push es
    push cs
    pop ds
    les bx, [request]
    mov word [es:bx+3], 8103h       ; unknown command
    cmp byte [es:bx+2], 0
    jne .done
    mov word [es:bx+3], 100h
    mov word [es:bx+14], resident_end
    mov [es:bx+16], cs
%ifndef SIM
    mov ax, 4300h
    int 2fh
    cmp al, 80h                     ; an XMS manager already owns memory
    je .refused
%endif
    call detect_memory
%ifndef SIM
    mov dx, failed_text
    cmp byte [detected], 0
    je .print
    mov dx, small_text
    cmp byte [detected], 64
    jne .print
    mov dx, large_text
    jmp .print
.refused:
    mov dx, owned_text
.print:
    mov ah, 9
    int 21h
%endif
.done:
    pop es
    pop ds
    popad
    popf
    retf
resident_end:

detect_memory:
    pushf
    cli
    mov byte [detected], 0
    mov byte [low_ok], 0
    mov byte [high_ok], 0
    mov eax, cr0
    test al, 1
    jnz .unsupported                ; never switch an existing protected host
    mov [old_cr0], eax
    sgdt [old_gdtr]
    mov [old_ss], ss
    mov ax, cs
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
    movzx eax, word [old_ss]
    shl eax, 4
    mov [stack_desc+2], ax
    shr eax, 16
    mov [stack_desc+4], al
    in al, 0f2h
    and al, 1
    mov [old_a20], al
    out 0f2h, al
    lgdt [gdtr]
    mov eax, [old_cr0]
    or al, 1
    mov cr0, eax
    jmp 08h:protected
.unsupported:
    popf
    ret

protected:
    mov ax, 10h
    mov ds, ax
    mov ax, 18h
    mov ss, ax
    mov ax, 20h
    mov es, ax
    mov ebx, 1
    mov si, saved
.save:
    call address
    mov eax, [es:edi]
    mov [si], eax
    add si, 4
    call next_mb
    jb .save
    mov ebx, 1
.write:
    call address
    mov eax, edi
    xor eax, 5a9836c7h
    mov [es:edi], eax
    call next_mb
    jb .write
    mov ebx, 1
.verify:
    call address
    mov eax, edi
    xor eax, 5a9836c7h
    cmp [es:edi], eax
    jne .next
    cmp ebx, 15
    ja .high
    inc byte [low_ok]
    jmp .next
.high:
    inc byte [high_ok]
.next:
    call next_mb
    jb .verify
    mov ebx, 1
    mov si, saved
.restore:
    call address
    mov eax, [si]
    mov [es:edi], eax
    add si, 4
    call next_mb
    jb .restore
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
    mov ax, [old_ss]
    mov ss, ax
    lgdt [old_gdtr]
    mov al, [old_a20]
    add al, 2
    out 0f6h, al
    cmp byte [low_ok], 14
    jne .done
    mov al, [high_ok]
    test al, al
    jz .publish
    cmp al, 48
    jne .done                       ; inconsistent/aliased map: advertise none
.publish:
    mov ah, 0
    xor dx, dx
    mov es, dx
    mov byte [es:401h], 112          ; 14 MB in 128 KB units
    mov [es:594h], ax               ; mapped MB above 16 MB, skipping aperture
    ; This initializer has just executed 386 protected-mode memory probes.
    ; The legacy BIOS sets the V30 flag unconditionally. Preserve its other
    ; identification bits, but do not misreport this verified 386+ CPU as V30.
    and byte [es:501h], 0bfh
    add al, 16
    mov [detected], al
.done:
    popf
    ret
address:
    mov edi, ebx
    shl edi, 20
    add edi, 100h
    ret
next_mb:
    inc ebx
    cmp ebx, 15
    jne .limit
    inc ebx
.limit:
    cmp ebx, 64
    ret
align 8
gdt:
    dq 0
code_desc: dq 00009a000000ffffh
data_desc: dq 000092000000ffffh
stack_desc: dq 000092000000ffffh
    dq 00cf92000000ffffh
gdtr: dw 39
    dd 0
old_gdtr: times 6 db 0
old_cr0: dd 0
old_ss: dw 0
old_a20: db 0
low_ok: db 0
high_ok: db 0
detected: db 0
saved: times 62 dd 0
failed_text: db 'Z98MEM: no supported extended RAM map; BIOS counts unchanged.',13,10,'$'
owned_text: db 'Z98MEM: load before XMS manager; BIOS counts unchanged.',13,10,'$'
small_text: db 'Z98MEM: 16 MB map, 14 MB extended RAM detected.',13,10,'$'
large_text: db 'Z98MEM: 64 MB map, 62 MB extended RAM detected.',13,10,'$'

%ifdef SIM
simulation:
    cli
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ax, 2200h                  ; DOS may supply a stack outside driver CS
    mov ss, ax
    mov sp, 0fffeh
    mov bx, packet
    push cs
    call strategy
    push cs
    call interrupt
    cmp word [packet+3], 100h
    jne .failed
    cmp byte [detected], TOP_MB
    jne .failed
    mov byte [packet+2], 7
    push cs
    call interrupt
    cmp word [packet+3], 8103h
    jne .failed
    mov ax, 600dh
    jmp .report
.failed:
    mov ax, 0deadh
.report:
    mov dx, 7ff0h
    out dx, ax
    hlt
    jmp $
packet: times 32 db 0
%endif
