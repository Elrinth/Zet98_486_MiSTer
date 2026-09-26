; SPDX-License-Identifier: GPL-3.0-or-later
; Real-mode FLAGS/EFLAGS restoration and exact single-step return address.
; Run as the DOS shell on an isolated writable diagnostic floppy.
bits 16
cpu 486
org 100h
start:
    push cs
    pop ds
    pushfd
    pop dword [entry_flags]
    mov ax,3501h
    int 21h
    mov [old_int1],bx
    mov [old_int1+2],es
    mov dx,trap_handler
    mov ax,2501h
    int 21h
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,banner
    mov ah,9
    int 21h
    cli
    xor si,si
    mov di,4096
.roundtrip:
    mov byte [stage],'1'
    mov ax,si
    and ax,0cd5h
    or ax,2
    push ax
    popf
    pushf
    pop dx
    xor dx,ax
    test dx,0cd5h
    jnz failed
    mov byte [stage],'2'
    movzx eax,si
    shl eax,18
    and eax,40000h
    mov bx,si
    and bx,0cd5h
    or bx,2
    mov ax,bx
    push eax
    popfd
    pushfd
    pop edx
    xor edx,eax
    test edx,40cd5h
    jnz failed
    mov byte [stage],'3'
    mov ax,si
    and ax,0ffh
    mov ah,al
    sahf
    lahf
    and al,0d5h
    or al,2
    cmp al,ah
    jne failed
    cmp word [trap_count],0
    jne failed
    inc si
    dec di
    jnz .roundtrip

    mov byte [stage],'4'
    mov word [expected_ip],after_step
    push word 0102h          ; TF=1, IF=0; trap after the following NOP
    popf
    nop
after_step:
    cli
    cmp word [trap_count],1
    jne failed
    cmp byte [bad_trap],0
    jne failed
    cmp word [trap_ip],after_step
    jne failed
    pushf
    pop ax
    test ax,0100h
    jnz failed
    mov dword [status],'PASS'
    jmp finish
failed:
    cli
finish:
    cld
    push ds
    lds dx,[old_int1]
    mov ax,2501h
    int 21h
    pop ds
    push dword [entry_flags]
    popfd
    cld
    mov ax,[trap_count]
    mov di,count_hex
    call hex16
    mov ax,[trap_ip]
    mov di,ip_hex
    call hex16
    mov dx,report
    mov ah,9
    int 21h
    mov dx,filename
    mov ax,5b00h             ; never truncate an existing result
    xor cx,cx
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
    jmp halt
close_failed:
    mov ah,3eh
    int 21h
save_failed:
    mov dx,save_error
    mov ah,9
    int 21h
halt:
    sti
    hlt
    jmp halt

trap_handler:
    push bp
    mov bp,sp
    push ax
    inc word [cs:trap_count]
    mov ax,[ss:bp+2]
    mov [cs:trap_ip],ax
    cmp ax,[cs:expected_ip]
    je .known
    mov byte [cs:bad_trap],1
.known:
    and word [ss:bp+6],0feffh
    pop ax
    pop bp
    iret
critical_error:
    mov al,3
    iret
hex16:
    mov cx,4
.digit:
    rol ax,4
    mov bl,al
    and bl,15
    add bl,'0'
    cmp bl,'9'
    jbe .store
    add bl,7
.store:
    mov [di],bl
    inc di
    loop .digit
    ret
entry_flags: dd 0
old_int1: dd 0
expected_ip: dw 0
trap_count: dw 0
trap_ip: dw 0
bad_trap: db 0
banner: db 13,10,'Z98 flag restoration / single-step test',13,10,'$'
report: db 13,10,'Z98 FLAGS: '
status: db 'FAIL'
    db ' stage='
stage: db '0'
    db ' traps='
count_hex: db '0000'
    db ' IP='
ip_hex: db '0000'
    db 13,10
report_end: db '$'
filename: db 'A:\Z98FLAGS.TXT',0
save_error: db 'Result save failed.',13,10,'$'
