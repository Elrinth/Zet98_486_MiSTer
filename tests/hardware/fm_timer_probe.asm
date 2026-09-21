; SPDX-License-Identifier: GPL-3.0-or-later
; Silent DOS FM-timer/IRQ12 diagnostic. Run on a disposable boot disk.
bits 16
cpu 8086
org 100h
start:
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
    mov dx,0a66eh
    mov al,1
    out dx,al                 ; mute board-86 FM/PSG output
    mov dx,0a468h
    xor al,al
    out dx,al                 ; stop PCM playback/IRQ
    mov ax,3027h
    call fmwrite
    mov ax,0029h
    call fmwrite
    mov ax,0f026h             ; timer B, 16 prescaled ticks
    call fmwrite
    mov ax,3514h
    int 21h
    mov [old_vector],bx
    mov [old_vector+2],es
    mov dx,handler
    mov ax,2514h
    int 21h
    cli
    in al,2
    mov [old_master],al
    and al,7fh
    out 2,al
    in al,0ah
    mov [old_slave],al
    and al,0efh
    out 0ah,al
    mov ax,0329h              ; enable FM timer IRQ sources only
    call fmwrite
    sti
    mov ah,2ch
    int 21h
    mov [start_second],dh
    mov ax,0a27h
    call fmwrite
.await:
    cmp byte [bad_irq],0
    jne cleanup
    cmp word [irq_count],100
    jae .passed
    mov ah,2ch
    int 21h
    mov al,dh
    sub al,[start_second]
    jnc .elapsed
    add al,60
.elapsed:
    cmp al,8
    jb .await
    jmp cleanup
.passed:
    mov byte [passed],1
cleanup:
    cli
    mov ax,0029h              ; mask IRQ even if old clear logic is broken
    call fmwrite
    mov ax,3027h
    call fmwrite
    mov al,20h
    out 8,al
    out 0,al
    mov al,[old_slave]
    out 0ah,al
    mov al,[old_master]
    out 2,al
    sti
    push ds
    lds dx,[old_vector]
    mov ax,2514h
    int 21h
    pop ds
    mov ax,[irq_count]
    mov di,fail_count+3
    mov cx,4
.hex:
    mov bl,al
    and bl,0fh
    add bl,'0'
    cmp bl,'9'
    jbe .digit
    add bl,7
.digit:
    mov [di],bl
    dec di
    shr ax,1
    shr ax,1
    shr ax,1
    shr ax,1
    loop .hex
    mov al,[bad_irq]
    add al,'0'
    mov [fail_reason],al
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
fmwrite:
    push ax
    push dx
    mov dx,188h
    out dx,al
    mov al,ah
    add dx,2
    out dx,al
    pop dx
    pop ax
    ret
handler:
    push ax
    push dx
    mov dx,188h
    in al,dx
    test al,2
    jnz .timer
    mov byte [cs:bad_irq],1
.timer:
    mov ax,2a27h
    call fmwrite
    mov dx,188h
    in al,dx
    test al,2
    jz .cleared
    mov byte [cs:bad_irq],2
.cleared:
    inc word [cs:irq_count]
    mov al,20h
    out 8,al
    out 0,al
    pop dx
    pop ax
    iret
critical_error:
    mov al,3
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
log_name: db 'Z98FM.TXT',0
pass_text: db 13,10,'PASS: 100 FM timer B IRQ12 deliveries,',13,10
    db 'status assertion/clear and cascaded PIC EOI.',13,10
    db 'FM muted. Music/audio quality not measured.',13,10,0
fail_text: db 13,10,'FAIL: FM timer IRQ12 test. IRQ count='
fail_count: db '0000',' reason='
fail_reason: db '0',13,10
    db 'Reason: 0=timeout, 1=missing flag, 2=clear lost.',13,10,0
times 0 * (1 / (($ - $$) <= 2011)) db 0
