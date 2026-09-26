; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored real-mode PC-98 IRQ0 test, fresh disposable DOS boot only.
; Timer 0 mode 3 / 140 Hz, RTC-bounded observation, no game/driver code.
; Restores original INT08/PIC mask and BIOS default 100Hz PIT divisor.
; This does NOT prove protected-mode DMX callback delivery.
bits 16
cpu 386
org 100h
start:
    push cs
    pop ds
    cld
    mov ax,3508h
    int 21h
    mov [old_vector],bx
    mov [old_vector+2],es
    mov dx,handler
    mov ax,2508h
    int 21h
    cli
    in al,2
    mov [old_mask],al
    mov al,0feh
    out 2,al
    mov al,36h
    out 77h,al
    mov ax,17554                 ; 2457600 / 140, matching the core clock
    out 71h,al
    mov al,ah
    out 71h,al
    sti
    call rtc_second
    jc cleanup
    mov [first],al
    mov bp,65535                 ; finite bound; host also enforces deadline
.poll:
    mov cx,4096
.idle:
    loop .idle
    call rtc_second
    jc cleanup
    sub al,[first]
    jnc .elapsed
    add al,60
.elapsed:
    cmp al,3
    jae .done
    dec bp
    jnz .poll
    jmp cleanup
.done:
    mov byte [clock_ok],1
cleanup:
    cli
    mov al,0ffh
    out 2,al
    mov ax,[cs:irq_count]
    mov [cs:final_count],ax
    mov al,36h
    out 77h,al
    xor al,al
    out 71h,al
    mov al,60h                   ; BIOS 100Hz reload
    out 71h,al
    mov al,20h
    out 0,al
    push ds
    lds dx,[old_vector]
    mov ax,2508h
    int 21h
    pop ds
    mov al,[old_mask]
    out 2,al
    sti
    mov dx,title
    mov ah,9
    int 21h
    mov ax,[final_count]
    call hex16
    mov dx,clock_text
    mov ah,9
    int 21h
    xor ax,ax
    mov al,[clock_ok]
    call hex16
    mov dx,newline
    mov ah,9
    int 21h
    mov ax,4c01h
    cmp byte [clock_ok],1
    jne .exit
    cmp word [final_count],3
    jb .exit
    xor al,al
.exit:
    int 21h
handler:
    push ax
    inc word [cs:irq_count]
    mov al,20h
    out 0,al
    pop ax
    iret
rtc_second:
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    push cs
    pop es
    mov bx,rtc
    xor ah,ah
    int 1ch
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    mov al,[rtc+5]
    mov ah,al
    and al,15
    cmp al,9
    ja .bad
    shr ah,4
    cmp ah,5
    ja .bad
    aad
    clc
    ret
.bad:
    stc
    ret
hex16:
    mov bx,ax
    mov cx,4
.digit:
    rol bx,4
    mov dl,bl
    and dl,15
    add dl,'0'
    cmp dl,'9'
    jbe .emit
    add dl,7
.emit:
    mov ah,2
    int 21h
    loop .digit
    ret
old_vector: dd 0
old_mask: db 0
first: db 0
clock_ok: db 0
irq_count: dw 0
final_count: dw 0
rtc: times 6 db 0
title: db 'PC-98 real-mode PIT mode3/140Hz IRQ0 count (hex): $'
clock_text: db ' / RTC elapsed >=3sec: $'
newline: db 13,10,'BIOS default PIT rate, original vector and PIC mask restored.',13,10,'$'
