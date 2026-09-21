; SPDX-License-Identifier: GPL-3.0-or-later
; Silent MPU-PC98II UART diagnostic for a disposable DOS boot disk.
; Enable the experimental UART option before booting this program.
; v2: exercises 100 reset/UART pairs (200 IRQ6 acknowledgements), with silent
; resets to leave UART mode between pairs, then sends
; a 134-byte noncommercial SysEx packet for independent HPS serial capture.
; Does not play notes. A PASS here alone does not certify the serial output.
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
    mov ax,350eh
    int 21h
    mov [old_vector],bx
    mov [old_vector+2],es
    mov dx,handler
    mov ax,250eh
    int 21h
    cli
    in al,2
    mov [old_master],al
    and al,0bfh
    out 2,al
    sti
    mov cx,100
.pair:
    mov al,0ffh
    call command
    jc cleanup
    mov al,03fh
    call command
    jc cleanup
    cmp cx,1
    je .last
    call leave_uart
    jc cleanup
.last:
    loop .pair
    cmp word [irq_count],200
    jne cleanup
    cmp byte [bad_irq],0
    jne cleanup
    mov si,header
    mov cx,5
.header:
    lodsb
    call send_byte
    jc cleanup
    loop .header
    xor ax,ax
    mov cx,128
.payload:
    call send_byte
    jc cleanup
    inc al
    loop .payload
    mov al,0f7h
    call send_byte
    jc cleanup
    ; Give the serial FIFO ample time to drain before the result is saved.
    call start_timeout
.drain:
    call elapsed
    cmp al,1
    jb .drain
    mov byte [passed],1
cleanup:
    cli
    mov al,[old_master]
    out 2,al
    mov al,20h
    out 0,al
    sti
    push ds
    lds dx,[old_vector]
    mov ax,250eh
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
    mov si,fail_text
    cmp byte [passed],1
    jne .text
    mov si,pass_text
.text:
    mov [message],si
    xor cx,cx
.print:
    lodsb
    test al,al
    jz .save
    push cx
    push si
    mov dl,al
    mov ah,2
    int 21h
    pop si
    pop cx
    inc cx
    jmp .print
.save:
    mov [length],cx
    mov dx,log_name
    xor cx,cx
    mov ah,3ch
    int 21h
    jc halt
    mov bx,ax
    mov dx,[message]
    mov cx,[length]
    mov ah,40h
    int 21h
    jc halt
    cmp ax,[length]
    jne halt
    mov ah,3eh
    int 21h
    mov ah,0dh
    int 21h
halt:
    sti
    hlt
    jmp halt

; Roland's FF command in UART mode clears it without returning FE/IRQ.
leave_uart:
    push ax
    push bx
    push dx
    mov bx,[irq_count]
    mov dx,0e0d2h
    mov al,0ffh
    out dx,al
    mov ah,16
.wait:
    in al,dx
    test al,80h
    jz .bad
    dec ah
    jnz .wait
    cmp bx,[irq_count]
    jne .bad
    clc
    jmp short .done
.bad:
    stc
.done:
    pop dx
    pop bx
    pop ax
    ret
command:
    push bx
    push dx
    mov bx,[irq_count]
    inc bx
    mov dx,0e0d2h
    out dx,al
    call start_timeout
.wait:
    cmp word [irq_count],bx
    je .done
    call elapsed
    cmp al,3
    jb .wait
    stc
    jmp .exit
.done:
    clc
.exit:
    pop dx
    pop bx
    ret
send_byte:
    push ax
    push dx
    call start_timeout
.wait:
    mov dx,0e0d2h
    in al,dx
    test al,40h
    jz .ready
    call elapsed
    cmp al,3
    jb .wait
    stc
    jmp .exit
.ready:
    pop dx
    pop ax
    push dx
    mov dx,0e0d0h
    out dx,al
    pop dx
    clc
    ret
.exit:
    pop dx
    pop ax
    ret
start_timeout:
    push ax
    push cx
    push dx
    mov ah,2ch
    int 21h
    mov [start_second],dh
    pop dx
    pop cx
    pop ax
    ret
elapsed:
    push cx
    push dx
    mov ah,2ch
    int 21h
    mov al,dh
    sub al,[start_second]
    jnc .done
    add al,60
.done:
    pop dx
    pop cx
    ret
handler:
    push ax
    push dx
    mov dx,0e0d2h
    in al,dx
    test al,80h
    jnz .bad
    sub dx,2
    in al,dx
    cmp al,0feh
    je .ack
.bad:
    mov byte [cs:bad_irq],1
.ack:
    inc word [cs:irq_count]
    mov al,20h
    out 0,al
    pop dx
    pop ax
    iret
critical_error:
    mov al,3
    iret
old_vector: dd 0
old_master: db 0
irq_count: dw 0
bad_irq: db 0
passed: db 0
start_second: db 0
message: dw 0
length: dw 0
header: db 0f0h,07dh,'Z98'
log_name: db 'Z98MPU.TXT',0
pass_text: db 13,10,'PASS: 200 MPU UART ACK IRQ6 deliveries and EOI.',13,10
    db '134-byte silent SysEx queued. Verify HPS capture separately.',13,10
    db 'Intelligent mode and music/audio quality not tested.',13,10,0
fail_text: db 13,10,'FAIL: MPU UART ACK/IRQ/transmit timeout. IRQ count='
fail_count: db '0000',13,10,0
times 0 * (1 / (($ - $$) <= 2011)) db 0
