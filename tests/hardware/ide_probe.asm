; SPDX-License-Identifier: GPL-3.0-or-later
; Runs from a disposable floppy. Writes ONLY after checking a 1 MB raw disk
; and its exact diagnostic signature. Sector 17 is the sole write target.
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
    mov dx,074ch
    mov al,2
    out dx,al
    mov dx,0432h
    xor al,al
    out dx,al
    mov dx,064ch
    mov al,0e0h
    out dx,al
    mov dx,064eh
    in al,dx
    cmp al,50h
    jne finish
    mov ax,3511h
    int 21h
    mov [old_vector],bx
    mov [old_vector+2],es
    mov dx,handler
    mov ax,2511h
    int 21h
    push ds
    pop es
    cli
    in al,2
    mov [old_master],al
    and al,7fh
    out 2,al
    in al,0ah
    mov [old_slave],al
    and al,0fdh
    out 0ah,al
    mov byte [installed],1
    mov dx,074ch
    xor al,al
    out dx,al
    sti
    mov byte [fail_stage],'1'
    mov al,0ech
    call command
    call wait_irq
    jc cleanup
    call receive
    cmp word [buffer+120],2048
    jne cleanup
    cmp word [buffer+122],0
    jne cleanup
    mov byte [fail_stage],'2'
    xor al,al
    call address
    mov al,20h
    call command
    call wait_irq
    jc cleanup
    call receive
    mov si,signature
    mov di,buffer
    mov cx,signature_end-signature
    repe cmpsb
    jne cleanup
    ; Capacity and the marker have both been verified before any disk write.
    mov byte [fail_stage],'3'
    mov al,17
    call address
    mov al,30h
    call command
    mov dx,074ch
    in al,dx
    cmp al,58h
    jne cleanup
    mov dx,0640h
    xor si,si
    mov cx,256
.write:
    mov ax,si
    xor ax,0a55ah
    out dx,ax
    inc si
    loop .write
    call wait_irq
    jc cleanup
    mov byte [fail_stage],'4'
    mov al,17
    call address
    mov al,20h
    call command
    call wait_irq
    jc cleanup
    call receive
    mov di,buffer
    xor si,si
    mov cx,256
.verify:
    mov ax,si
    xor ax,0a55ah
    scasw
    jne cleanup
    inc si
    loop .verify
    cmp word [irq_count],4
    jne cleanup
    mov byte [passed],1
cleanup:
    cli
    mov dx,074ch
    mov al,6
    out dx,al
    mov al,2
    out dx,al
    mov al,[old_slave]
    out 0ah,al
    mov al,[old_master]
    out 2,al
    sti
    push ds
    lds dx,[old_vector]
    mov ax,2511h
    int 21h
    pop ds
finish:
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
    mov ah,3eh
    int 21h
    mov ah,0dh
    int 21h
halt:
    sti
    hlt
    jmp halt
address:
    mov dx,0646h
    out dx,al
    mov dx,0644h
    mov al,1
    out dx,al
    mov dx,0648h
    xor al,al
    out dx,al
    mov dx,064ah
    out dx,al
    mov dx,064ch
    mov al,0e0h
    out dx,al
    ret
command:
    mov bx,[irq_count]
    mov dx,064eh
    out dx,al
    ret
wait_irq:
    mov ah,2ch
    int 21h
    mov [start_second],dh
.await:
    cmp [irq_count],bx
    jne .done
    mov ah,2ch
    int 21h
    mov al,dh
    sub al,[start_second]
    jnc .elapsed
    add al,60
.elapsed:
    cmp al,3
    jb .await
    stc
    ret
.done:
    mov dx,074ch
    in al,dx
    test al,81h
    jnz .bad
    clc
    ret
.bad:
    stc
    ret
receive:
    mov di,buffer
    mov cx,256
    mov dx,0640h
.read:
    in ax,dx
    stosw
    loop .read
    ret
handler:
    push ax
    push dx
    mov dx,064eh
    in al,dx
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
installed: db 0
passed: db 0
start_second: db 0
message: dw 0
length: dw 0
log_name: db 'Z98IDE.TXT',0
signature: db 'Z98 IDE DIAGNOSTIC ONLY',13,10
signature_end:
pass_text: db 13,10,'PASS: ATA IDENTIFY, 1MB raw image signature,',13,10
    db 'sector 17 write/read checksum, four IRQ9 deliveries.',13,10,0
fail_text: db 13,10,'FAIL: PC98 raw IDE diagnostic, stage='
fail_stage: db '0',13,10,0
times 0 * (1 / (($ - $$) <= 2011)) db 0
buffer equ 2000h
