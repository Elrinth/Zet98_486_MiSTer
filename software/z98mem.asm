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

%include "z98mem_probe.inc"
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
