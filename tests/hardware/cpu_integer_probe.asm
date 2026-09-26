; SPDX-License-Identifier: GPL-3.0-or-later
; Disposable DOS shell. Shares architectural vectors with the RTL smoke test.
bits 16
cpu 486
org 100h
    cli
    mov ax,cs
    mov ss,ax
    mov sp,0fffeh
    mov ds,ax
    mov es,ax
    cld
    sti
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,banner
    call puts
    cli
%include "tests/z486_integer_cases.inc"
%include "tests/z486_elapsed_cases.inc"
    mov word [status],'PA'
    mov word [status+2],'SS'
fail:
    sti
    cld
    mov al,[0x27d0]
    add al,'0'
    mov [stage],al
    mov dx,report
    call puts
    mov dx,filename
    xor cx,cx
    mov ax,5b00h
    int 21h
    jc save_failed
    mov bx,ax
    mov dx,report
    mov cx,report_end-report
    mov ah,40h
    int 21h
    jc close_failed
    cmp ax,report_end-report
    jne close_failed
    mov ah,3eh
    int 21h
    jc save_failed
    mov ah,0dh
    int 21h
    jmp park
close_failed:
    mov ah,3eh
    int 21h
save_failed:
    mov dx,save_error
    call puts
park:
    sti
park_hlt:
    hlt
    jmp park
critical_error:
    mov al,3
    iret
puts:
    mov ah,9
    int 21h
    ret
banner: db 13,10,'Z98 integer arithmetic / clock conversion probe',13,10,'$'
report: db 'Z98 INTEGER: '
status: db 'FAIL stage='
stage: db '0',13,10
report_end: db '$'
filename: db 'A:\Z98INT.TXT',0
save_error: db 'Result save failed.',13,10,'$'
dw arith_after_mul8-$$,elapsed_after_sub-$$,park_hlt-$$
