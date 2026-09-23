; SPDX-License-Identifier: GPL-3.0-or-later
; Run the user's unchanged ONGCHK.COM detection procedure on the real core.
; ONGCHK_FILE must be the verified 193-byte Rusty file. The private binary is
; supplied locally while preparing a disposable test disk, never vendored.
bits 16
cpu 8086
org 100h
    jmp near wrapper
    incbin ONGCHK_FILE,3
    db 0,0                    ; original procedure's 01C1/01C2 variables
wrapper:
    cli
    mov ax,cs
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,0fffeh
    sti
    call 113h                 ; original sound-detection procedure, no patch
    mov al,0
    jc .result
    mov al,[1c2h]
    inc al                    ; exactly the original program's exit code
.result:
    add al,'0'
    mov [code_digit],al
    cmp al,'3'                 ; 3 = detected 86 board with extended OPNA
    jne .save
    mov word [outcome],'PA'
    mov word [outcome+2],'SS'
.save:
    mov dx,filename
    xor cx,cx
    mov ah,3ch
    int 21h
    jc .disk_failed
    mov bx,ax
    mov dx,message
    mov cx,message_end-message
    mov ah,40h
    int 21h
    jc .disk_failed
    cmp ax,message_end-message
    jne .disk_failed
    mov ah,3eh
    int 21h
    jc .disk_failed
    mov dx,message
    mov ah,9
    int 21h
    jmp .halt
.disk_failed:
    mov dx,disk_error
    mov ah,9
    int 21h
.halt:
    sti
    hlt
    jmp .halt
filename: db 'Z98SND.TXT',0
message:
outcome: db 'FAIL Rusty ONGCHK sound detection: '
code_digit: db '?'
    db ' (3 = PC-9801-86 / OPNA)',13,10
message_end: db '$'
disk_error: db 'FAIL writing sound-detection result',13,10,'$'
