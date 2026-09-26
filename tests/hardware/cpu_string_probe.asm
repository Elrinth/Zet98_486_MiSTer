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
    mov word [0x27c0],0
    sti
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,banner
    call puts
    mov ax,cs
    cmp ax,3000h
    jae fail
    cmp word [2],9000h
    jb fail
    cli
%include "tests/z486_string_cases.inc"
    mov word [status],'PA'
    mov word [status+2],'SS'
fail:
    sti
    cld
    mov ax,[0x27c0]
    mov bl,10
    div bl
    add ax,3030h
    mov [stage],al
    mov [stage+1],ah
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
banner: db 13,10,'Z98 REP fill/compare / indirect branch probe',13,10,'$'
report: db 'Z98 STRINGS: '
status: db 'FAIL stage='
stage: db '00',13,10
report_end: db '$'
filename: db 'A:\Z98STR.TXT',0
save_error: db 'Result save failed.',13,10,'$'
dw z486_string_stored-$$,z486_string_mismatch-$$,park_hlt-$$
