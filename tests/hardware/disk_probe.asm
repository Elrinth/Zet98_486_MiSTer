; SPDX-License-Identifier: GPL-3.0-or-later
; 8086 DOS shell for an isolated copy of the user's PC-98 system floppy.
; Checks drive letters through DOS and saves results on that disposable copy.
; Does not alter the supplied source images or any core configuration.
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
    mov ah, 19h
    int 21h
    add al, 'A'
    mov [default_letter], al
    mov si, default_text
    call puts
    mov si, equipment_text
    call puts
    xor ax, ax
    mov es, ax
    mov ax, [es:055ch]
    push cs
    pop es
    call hexword
    mov si, drives_text
    call puts
    mov dl, [default_letter]
    sub dl, 'A'
    mov ah, 0eh
    int 21h
    call hexbyte
    mov si, newline
    call puts
    mov si, b_space_text
    call puts
    mov dl, 2
    mov ah, 36h
    int 21h
    call hexword
    mov si, newline
    call puts
    mov si, names
.next:
    lodsw
    test ax, ax
    jz .save
    push si
    mov dx, ax
    call probe
    pop si
    jmp .next
.save:
    mov si, saving
    call puts
    mov dx, log_name
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc .save_error
    mov bx, ax
    mov dx, log_buffer
    mov cx, [log_pos]
    sub cx, dx
    mov ah, 40h
    int 21h
    pushf
    push ax
    mov ah, 3eh
    int 21h
    pop ax
    popf
    jc .save_error
    mov ah, 0dh
    int 21h
    mov si, finished
    call puts
    jmp .halt
.save_error:
    push ax
    mov si, failed
    call puts
    pop ax
    call hexword
    mov si, newline
    call puts
.halt:
    sti
    hlt
    jmp .halt

critical_error:
    mov al, 3                   ; DOS Fail, rather than an interactive prompt.
    iret

probe:
    mov si, dx
    call puts
    mov ax, 3d00h               ; Open read-only, including zero-byte markers.
    int 21h
    jc .error
    mov [file_handle], ax
    mov si, opened
    call puts
    mov bx, [file_handle]
    mov cx, 16
    mov dx, read_buffer
    mov ah, 3fh
    int 21h
    jc .read_error
    push ax
    call hexword
    mov si, data_text
    call puts
    pop cx
    mov si, read_buffer
.bytes:
    jcxz .close
    lodsb
    xor ah, ah
    call hexbyte
    push si
    mov si, space
    call puts
    pop si
    loop .bytes
.close:
    mov bx, [file_handle]
    mov ah, 3eh
    int 21h
    mov si, newline
    call puts
    ret
.read_error:
    push ax
    mov si, read_failed
    call puts
    pop ax
    call hexword
    jmp .close
.error:
    push ax
    mov si, failed
    call puts
    pop ax
    call hexword
    mov si, newline
    call puts
    ret

hexword:
    push ax
    mov al, ah
    call hexbyte
    pop ax
hexbyte:
    push ax
    push cx
    mov cl, 4
    shr al, cl
    call nibble
    pop cx
    pop ax
    push ax
    and al, 15
    call nibble
    pop ax
    ret
nibble:
    and al, 15
    add al, '0'
    cmp al, '9'
    jbe putchar
    add al, 7
putchar:
    push ax
    push dx
    push di
    mov di, [log_pos]
    cmp di, log_buffer + 2048
    jae .screen
    mov [di], al
    inc word [log_pos]
.screen:
    mov dl, al
    mov ah, 2
    int 21h
    pop di
    pop dx
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

title: db 13,10,'Zet98 DOS disk probe v2',13,10,0
equipment_text: db 'BIOS drive mask [055C]=',0
drives_text: db ' DOS drive count=',0
b_space_text: db 'B: free-space query AX=',0
default_text: db 'Default drive: '
default_letter: db '?',13,10,0
opened: db ' OK read=',0
data_text: db ' data=',0
failed: db ' ERROR=',0
read_failed: db 'READ ERROR=',0
saving: db 'Saving Z98DIAG.TXT on the disposable system disk.',13,10,0
finished: db 'Probe finished. Leave this screen for inspection.',13,10,0
newline: db 13,10,0
space: db ' ',0
log_name: db 'Z98DIAG.TXT',0
names: dw a_sys, b_sys, a_op, b_op, a_loader, b_loader, 0
a_sys: db 'A:\SYS_DISK',0
b_sys: db 'B:\SYS_DISK',0
a_op: db 'A:\OP_DISK',0
b_op: db 'B:\OP_DISK',0
a_loader: db 'A:\MGXLOAD.BIN',0
b_loader: db 'B:\MGXLOAD.BIN',0
file_handle: dw 0
log_pos: dw 0
read_buffer: times 16 db 0

; Keep the COM small enough to replace BOOT.COM without reallocating clusters.
times 0 * (1 / (($ - $$) <= 2011)) db 0
log_buffer equ 0x2000
