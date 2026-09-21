; SPDX-License-Identifier: GPL-3.0-or-later
; 8086-compatible DOS benchmark for a disposable PC-98 System disk.
; Replaces BOOT.COM without reallocating its original 2011-byte allocation.
; Uses DOS hundredths-of-a-second time, retaining interrupts. A kernel must
; finish within one hour; zero elapsed time is below the timer's resolution.
bits 16
org 100h
start:
    cli
    mov ax, cs
    mov ss, ax
    mov sp, 0xfffe
    sti
    mov ds, ax
    mov es, ax
    cld
    mov word [log_pos], log_buffer
    mov dx, critical_error
    mov ax, 2524h
    int 21h
    mov si, title
    call puts
    call read_clock
    mov [start_lo], ax
    mov [start_hi], dx
    xor bx, bx
    xor si, si
    mov bp, 32
.alu_outer:
    mov cx, 4096
.alu:
    add bx, 3
    inc si
    dec cx
    jnz .alu
    dec bp
    jnz .alu_outer
    call elapsed
    or bx, bx
    jnz fail
    or si, si
    jnz fail
    mov si, alu_text
    call result

    mov di, 0x6000
    mov cx, 1024
    mov ax, 0xa55a
    rep stosw
    call read_clock
    mov [start_lo], ax
    mov [start_hi], dx
    mov bp, 128
.ram_outer:
    mov si, 0x6000
    mov di, 0x7000
    mov cx, 1024
.ram:
    mov ax, [si]
    mov [di], ax
    add si, 2
    add di, 2
    dec cx
    jnz .ram
    dec bp
    jnz .ram_outer
    call elapsed
    push dx
    push ax
    mov si, 0x7000
    mov cx, 1024
.verify:
    lodsw
    cmp ax, 0xa55a
    jne fail
    loop .verify
    pop ax
    pop dx
    mov si, ram_text
    call result
    mov si, passed
    call puts
    jmp save
fail:
    mov si, failed
    call puts
save:
    mov dx, log_name
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc save_error
    mov bx, ax
    mov dx, log_buffer
    mov cx, [log_pos]
    sub cx, dx
    mov [write_length], cx
    mov ah, 40h
    int 21h
    jc save_error
    cmp ax, [write_length]
    jne save_error
    mov ah, 3eh
    int 21h
    jc save_error
    mov ah, 0dh
    int 21h
    mov si, finished
    call puts
halt:
    sti
    hlt
    jmp halt
save_error:
    mov si, save_failed
    call puts
    jmp halt
critical_error:
    mov al, 3
    iret

; DX:AX = hundredths since this hour; preserves BX/CX/SI/DI/BP/ES.
read_clock:
    push bx
    push cx
    push si
    push di
    push bp
    push es
    mov ah, 2ch
    int 21h
    mov si, dx
    xor ax, ax
    mov al, cl
    mov bx, 60
    mul bx
    mov bx, si
    mov bl, bh
    xor bh, bh
    add ax, bx
    mov bx, 100
    mul bx
    mov bx, si
    xor bh, bh
    add ax, bx
    adc dx, 0
    pop es
    pop bp
    pop di
    pop si
    pop cx
    pop bx
    ret
elapsed:
    call read_clock
    sub ax, [start_lo]
    sbb dx, [start_hi]
    jnc .done
    add ax, 0x7e40             ; 360000 hundredths per hour
    adc dx, 5
.done:
    ret
result:
    call puts
    call decimal32
    mov si, units
    call puts
    ret
decimal32:
    push bx
    push cx
    push si
    xor cx, cx
    mov bx, 10
.digit:
    mov si, ax
    mov ax, dx
    xor dx, dx
    div bx
    xchg ax, si
    div bx
    push dx
    inc cx
    mov dx, si
    or si, ax
    jnz .digit
.print:
    pop ax
    add al, '0'
    call putchar
    loop .print
    pop si
    pop cx
    pop bx
    ret
putchar:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov di, [log_pos]
    cmp di, log_buffer+2048
    jae .screen
    mov [di], al
    inc word [log_pos]
.screen:
    mov dl, al
    mov ah, 2
    int 21h
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
puts:
    push ax
    push si
.char:
    lodsb
    test al, al
    jz .done
    call putchar
    jmp .char
.done:
    pop si
    pop ax
    ret
title: db 13,10,'Zet98 CPU benchmark v1',13,10,'DOS clock; 131072 iterations per kernel.',13,10,0
alu_text: db 'ALU elapsed: ',0
ram_text: db 'RAM copy elapsed: ',0
units: db ' hundredths (0 = below resolution)',13,10,0
passed: db 'PASS: ALU and RAM checksums.',13,10,0
failed: db 'FAIL: kernel checksum.',13,10,0
finished: db 'Saved Z98PERF.TXT. Benchmark finished.',13,10,0
save_failed: db 'ERROR saving Z98PERF.TXT.',13,10,0
log_name: db 'Z98PERF.TXT',0
log_pos: dw 0
start_lo: dw 0
start_hi: dw 0
write_length: dw 0
times 0 * (1 / (($ - $$) <= 2011)) db 0
log_buffer equ 0x2000
