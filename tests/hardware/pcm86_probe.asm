; SPDX-License-Identifier: GPL-3.0-or-later
; Disposable DOS boot diagnostic. Keeps PCM muted; tests registers, FIFO and
; two real IRQ12 deliveries. Does not measure analog/HDMI audio quality.
bits 16
cpu 8086
org 100h
start:
    cli
    mov ax, cs
    mov ss, ax
    mov sp, 0fffeh
    mov ds, ax
    mov es, ax
    cld
    sti
    mov dx, critical_error
    mov ax, 2524h
    int 21h
    mov dx, 0a460h
    in al, dx
    and al, 0f0h
    cmp al, 40h
    jne fail_early
    mov dx, 0a66eh
    mov al, 1
    out dx, al
    ; Verify physical FIFO capacity/status without starting the DAC.
    call reset_fifo
    mov dx, 0a46ah
    mov al, 32h
    out dx, al
    mov dx, 0a46ch
    mov cx, 32768
    xor ax, ax
.fill:
    out dx, al
    loop .fill
    mov dx, 0a466h
    in al, dx
    and al, 0c0h
    cmp al, 80h
    jne fail_early
    call reset_fifo
    mov dx, 0a466h
    in al, dx
    and al, 0c0h
    cmp al, 40h
    jne fail_early
    mov ax, 3514h
    int 21h
    mov [old_vector], bx
    mov [old_vector+2], es
    mov dx, handler
    mov ax, 2514h
    int 21h
    cli
    in al, 2
    mov [old_master], al
    and al, 7fh
    out 2, al
    in al, 0ah
    mov [old_slave], al
    and al, 0efh
    out 0ah, al
    sti
    mov bp, 2
.round:
    call reset_fifo
    mov dx, 0a46ch
    mov cx, 1024
    xor ax, ax
.data:
    out dx, al
    loop .data
    mov dx, 0a468h
    mov al, 20h
    out dx, al
    mov dx, 0a46ah
    xor al, al
    out dx, al             ; refill threshold 128 bytes
    mov bx, [irq_count]
    mov ah, 2ch
    int 21h
    mov [start_second], dh
    mov dx, 0a468h
    mov al, 0b0h           ; 44.1 kHz stereo16 playback plus IRQ
    out dx, al
.await:
    cmp [irq_count], bx
    jne .received
    mov ah, 2ch
    int 21h
    mov al, dh
    sub al, [start_second]
    jnc .elapsed
    add al, 60
.elapsed:
    cmp al, 3
    jb .await
    jmp cleanup
.received:
    cmp byte [bad_irq], 0
    jne cleanup
    dec bp
    jnz .round
    cmp word [irq_count], 2
    jne cleanup
    mov byte [passed], 1
cleanup:
    cli
    call reset_fifo
    mov al, [old_slave]
    out 0ah, al
    mov al, [old_master]
    out 2, al
    sti
    push ds
    lds dx, [old_vector]
    mov ax, 2514h
    int 21h
    pop ds
fail_early:
    mov si, fail_text
    cmp byte [passed], 1
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
    jc halt
    mov bx, ax
    mov dx, [message]
    mov cx, [length]
    mov ah, 40h
    int 21h
    jc halt
    cmp ax, [length]
    jne halt
    mov ah, 3eh
    int 21h
    jc halt
    mov ah, 0dh
    int 21h
halt:
    sti
    hlt
    jmp halt
reset_fifo:
    mov dx, 0a468h
    mov al, 8
    out dx, al
    xor al, al
    out dx, al
    ret
handler:
    push ax
    push dx
    mov dx, 0a468h
    in al, dx
    test al, 10h
    jnz .pcm
    mov byte [cs:bad_irq], 1
.pcm:
    xor al, al
    out dx, al             ; stop and acknowledge before PIC EOI
    inc word [cs:irq_count]
    mov al, 20h
    out 8, al
    out 0, al
    pop dx
    pop ax
    iret
critical_error:
    mov al, 3
    iret
old_vector: dd 0
old_master: db 0
old_slave: db 0
irq_count: dw 0
bad_irq: db 0
passed: db 0
start_second: db 0
message: dw 0
length: dw 0
log_name: db 'Z98PCM.TXT',0
pass_text: db 13,10,'PASS: 86 board ID, 32768-byte FIFO full/empty/reset,',13,10
    db 'two PCM IRQ12 deliveries with status, acknowledgement and EOI.',13,10
    db 'PCM muted throughout. Audio output quality not measured.',13,10,0
fail_text: db 13,10,'FAIL: PCM86 ID, FIFO status or interrupt delivery.',13,10,0
times 0 * (1 / (($ - $$) <= 2011)) db 0
