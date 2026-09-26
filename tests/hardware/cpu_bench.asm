; SPDX-License-Identifier: GPL-3.0-or-later
; 8086-compatible DOS benchmark for a disposable PC-98 System disk.
; Replaces BOOT.COM without reallocating its original 2011-byte allocation.
; Install as the disk's actual CONFIG.SYS SHELL (some fixtures use Z98FONT.COM).
; Uses DOS time with interrupts enabled. Synchronizes to a clock transition,
; then repeats each kernel for at least ten reported seconds. A run must finish
; within one hour. Reported hundredths do not imply hundredth-second resolution.
bits 16
cpu 8086
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
%ifdef UPPER_CODE
    ; Optional comparison: the same arithmetic kernel at physical 90000h.
    ; A standalone DOS shell without memory managers owns this region only
    ; when its PSP allocation and program/stack placement satisfy both guards.
    mov ax, cs
    cmp ax, 6000h
    ja fail
    cmp word [2], 9100h
    jb fail
    mov ax, 9000h
    mov es, ax
    mov si, upper_kernel
    xor di, di
    mov cx, upper_kernel_end-upper_kernel
    rep movsb
    push cs
    pop es
%endif
    call start_timer
.alu_next:
%ifdef UPPER_CODE
    call 9000h:0
%else
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
%endif
    call elapsed
    or bx, bx
    jnz fail
    or si, si
    jnz fail
    inc word [batches]
    or dx, dx
    jnz .alu_done
    cmp ax, 1000
    jb .alu_next
.alu_done:
    mov si, alu_text
    call result

    mov di, 0x6000
    mov cx, 1024
    mov ax, 0xa55a
    rep stosw
    call start_timer
.ram_next:
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
    inc word [batches]
    or dx, dx
    jnz .ram_done
    cmp ax, 1000
    jb .ram_next
.ram_done:
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

    call start_timer
    mov [stack_top], sp
.stack_next:
    xor bx, bx
    mov bp, 128
.stack_outer:
    mov cx, 1024
.stack:
    push bx
    pop di
    cmp di, bx
    jne fail
    inc bx
    loop .stack
    dec bp
    jnz .stack_outer
    or bx, bx
    jnz fail
    cmp sp, [stack_top]
    jne fail
    call elapsed
    inc word [batches]
    or dx, dx
    jnz .stack_done
    cmp ax, 1000
    jb .stack_next
.stack_done:
    mov si, stack_text
    call result
    mov si, passed
    call puts
    jmp save
fail:
    mov si, failed
    call puts
save:
    mov byte [save_stage], 1
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
    mov byte [save_stage], 2
    mov ah, 40h
    int 21h
    jc save_error
    cmp ax, [write_length]
    jne save_error
    mov byte [save_stage], 3
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
    push ax
    mov si, save_failed
    call puts
    xor ax, ax
    mov al, [save_stage]
    xor dx, dx
    call decimal32
    mov si, error_ax_text
    call puts
    pop ax
    xor dx, dx
    call decimal32
    mov si, critical_text
    call puts
    mov ax, [critical_code]
    xor dx, dx
    call decimal32
    mov si, error_handle_text
    call puts
    mov ax, bx
    xor dx, dx
    call decimal32
    mov si, error_cs_text
    call puts
    mov ax, cs
    xor dx, dx
    call decimal32
    mov si, error_ds_text
    call puts
    mov ax, ds
    xor dx, dx
    call decimal32
    mov ah, 51h             ; DOS current process segment; failure report only
    int 21h
    push cs
    pop ds
    mov si, error_psp_text
    call puts
    mov ax, bx
    xor dx, dx
    call decimal32
    cmp bx, 0a000h
    jae .reported
    mov es, bx
    mov si, error_jft_text
    call puts
    mov di, 18h
    mov bp, 20              ; default DOS process handle table
.handles:
    xor ax, ax
    mov al, [es:di]
    xor dx, dx
    call decimal32
    mov al, ' '
    call putchar
    inc di
    dec bp
    jnz .handles
    mov si, error_jft_count_text
    call puts
    mov ax, [es:32h]
    xor dx, dx
    call decimal32
    mov si, error_jft_ptr_text
    call puts
    mov ax, [es:36h]
    xor dx, dx
    call decimal32
    mov al, ':'
    call putchar
    mov ax, [es:34h]
    xor dx, dx
    call decimal32
.reported:
    push ds
    pop es
    mov si, newline
    call puts
    jmp halt
critical_error:
    mov [cs:critical_code], di
    mov al, 3
    iret

; Synchronize to a DOS-clock transition to avoid a fractional first interval.
; Version 1 confirmed this clock advances on the test machine, but appears to
; expose whole seconds. Run for at least ten reported seconds, not a short loop.
start_timer:
    mov word [batches], 0
    call read_clock
    mov [start_lo], ax
    mov [start_hi], dx
.tick:
    call read_clock
    cmp ax, [start_lo]
    jne .started
    cmp dx, [start_hi]
    je .tick
.started:
    mov [start_lo], ax
    mov [start_hi], dx
    ret

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
    push dx
    push ax
    call puts
    mov ax, [batches]
    xor dx, dx
    call decimal32
    mov si, elapsed_text
    call puts
    pop ax
    pop dx
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
%ifdef UPPER_CODE
title: db 13,10,'Zet98 CPU benchmark v3: ALU at 90000h',13,10,'131072 iterations/block; at least 10s/kernel.',13,10,0
%else
title: db 13,10,'Zet98 CPU benchmark v3',13,10,'131072 iterations/block; at least 10s/kernel.',13,10,0
%endif
alu_text: db 'ALU blocks=',0
ram_text: db 'RAM copy blocks=',0
stack_text: db 'Stack blocks=',0
elapsed_text: db ' elapsed=',0
units: db ' hundredths',13,10,0
passed: db 'PASS: ALU, RAM and stack checksums.',13,10,0
failed: db 'FAIL: kernel checksum.',13,10,0
finished: db 'Saved Z98PERF.TXT. Benchmark finished.',13,10,0
save_failed: db 'ERROR saving Z98PERF.TXT. Stage=',0
error_ax_text: db ' AX=',0
critical_text: db ' INT24 DI=',0
error_handle_text: db ' BX=',0
error_cs_text: db ' CS=',0
error_ds_text: db ' DS=',0
error_psp_text: db ' PSP=',0
error_jft_text: db ' JFT=',0
error_jft_count_text: db ' COUNT=',0
error_jft_ptr_text: db ' PTR=',0
newline: db 13,10,0
log_name: db 'Z98PERF.TXT',0
save_stage: db 0
critical_code: dw 0ffffh
log_pos: dw 0
start_lo: dw 0
start_hi: dw 0
write_length: dw 0
batches: dw 0
stack_top: dw 0
%ifdef UPPER_CODE
upper_kernel:
    xor bx, bx
    xor si, si
    mov bp, 32
.outer:
    mov cx, 4096
.alu:
    add bx, 3
    inc si
    dec cx
    jnz .alu
    dec bp
    jnz .outer
    retf
upper_kernel_end:
%endif

times 0 * (1 / (($ - $$) <= 2011)) db 0
log_buffer equ 0x2000
