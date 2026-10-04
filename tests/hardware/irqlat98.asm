; IRQLAT.COM - interrupt latency while the disk BIOS reads floppies.
;
; Runs the system timer (IRQ0) at about 1 kHz with its own handler, which
; records the longest gap between two timer interrupts (timestamp port 5Eh,
; 0.83 ms units). Then reads 24 whole tracks of the 2HD floppy in drive 1
; (INT 1Bh AH=56h, 8 x 1024-byte sectors, seeking between them) and reports
; the longest gap seen during the reads. Music drivers run on interrupts like
; this one: a BIOS that keeps interrupts disabled while it waits for the
; drive shows gaps of a whole disk rotation or more.
;   nasm -f bin -o IRQLAT.COM irqlat98.asm
    org 100h

start:
    mov dx, msg_title
    call puts
    ; buffer: 8 KiB that does not cross a 64 KiB DMA boundary
    mov ax, cs
    shl ax, 4
    add ax, buf1
    add ax, 2000h
    jnc .b1
    jz .b1
    mov word [bufp], buf2
.b1:
    xor ax, ax
    mov es, ax
    cli
    mov ax, [es:8*4]
    mov [old8], ax
    mov ax, [es:8*4+2]
    mov [old8+2], ax
    mov word [es:8*4], tick
    mov [es:8*4+2], cs
    in al, 02h
    mov [oldimr], al
    and al, 0FEh
    out 02h, al
    mov al, 34h                     ; channel 0, mode 2 (rate generator)
    out 77h, al
    mov ax, 2458                    ; ~1 kHz at 2.4576 MHz (1.2 kHz at 1.9968)
    out 71h, al
    mov al, ah
    out 71h, al
    sti
    mov word [ticks], 0
    mov word [maxgap], 0
.idle:
    cmp word [ticks], 500
    jb .idle
    mov ax, [maxgap]
    mov [idlegap], ax
    mov word [maxgap], 0
    mov word [ticks], 0
    in ax, 5Eh
    mov [t0], ax
    xor si, si
.read:
    mov ax, si
    mov bl, 5
    mul bl                          ; cylinder = n * 5 mod 77
    mov bl, 77
    div bl
    mov cl, ah
    mov dh, 0
    test si, 1
    jz .h
    mov dh, 1
.h:
    mov dl, 1
    mov ch, 3
    mov bx, 2000h
    push cs
    pop es
    mov bp, [bufp]
    mov ax, 5690h                   ; read data, MFM, seek, 2HD unit 0
    int 1Bh
    jnc .ok
    inc word [errors]
    mov [laststat], ah
.ok:
    inc si
    cmp si, 24
    jb .read
    in ax, 5Eh
    sub ax, [t0]
    mov [elapsed], ax
    mov ax, [maxgap]
    mov [readgap], ax
    cli
    mov al, 30h
    out 77h, al
    xor al, al
    out 71h, al
    out 71h, al
    xor ax, ax
    mov es, ax
    mov ax, [old8]
    mov [es:8*4], ax
    mov ax, [old8+2]
    mov [es:8*4+2], ax
    mov al, [oldimr]
    out 02h, al
    sti
    mov dx, msg_idle
    call puts
    mov ax, [idlegap]
    call put_ms
    mov dx, msg_read
    call puts
    mov ax, [readgap]
    call put_ms
    mov dx, msg_time
    call puts
    mov ax, [elapsed]
    call put_ms
    mov dx, msg_ticks
    call puts
    mov ax, [ticks]
    call put_dec
    mov dx, msg_err
    call puts
    mov ax, [errors]
    call put_dec
    mov dx, msg_st
    call puts
    movzx ax, byte [laststat]
    call put_hex
    mov dx, msg_res
    call puts
    push ds
    xor ax, ax
    mov ds, ax
    mov si, 0564h
    mov di, 7
.rs:
    lodsb
    push si
    push di
    push ds
    push cs
    pop ds
    call put_hex
    mov dl, ' '
    mov ah, 2
    int 21h
    pop ds
    pop di
    pop si
    dec di
    jnz .rs
    pop ds
    mov dx, msg_nl
    call puts
    mov ax, 4C00h
    int 21h

tick:
    push ax
    push dx
    in ax, 5Eh
    mov dx, ax
    sub ax, [cs:last]
    mov [cs:last], dx
    cmp word [cs:ticks], 0
    je .first
    cmp ax, [cs:maxgap]
    jbe .first
    mov [cs:maxgap], ax
.first:
    inc word [cs:ticks]
    mov al, 20h
    out 00h, al
    pop dx
    pop ax
    iret

put_ms:
    mov dx, 834
    mul dx
    mov cx, 1000
    div cx
    call put_dec
    mov dx, msg_ms
    jmp puts

put_dec:
    xor cx, cx
    mov bx, 10
.d:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .d
.p:
    pop dx
    add dl, '0'
    mov ah, 2
    int 21h
    loop .p
    ret

put_hex:
    mov cx, 2
    mov bl, al
.hx:
    rol bl, 4
    mov dl, bl
    and dl, 0Fh
    add dl, '0'
    cmp dl, '9'
    jbe .hd
    add dl, 7
.hd:
    mov ah, 2
    int 21h
    loop .hx
    ret

puts:
    mov ah, 9
    int 21h
    ret

msg_title:  db 'IRQLAT: timer IRQ gaps while INT 1Bh reads drive 1 (2HD)', 13, 10, '$'
msg_idle:   db 'idle max gap: $'
msg_read:   db 13, 10, 'read max gap: $'
msg_time:   db 13, 10, '24 tracks in: $'
msg_ticks:  db 13, 10, 'ticks during reads: $'
msg_err:    db 13, 10, 'read errors: $'
msg_st:     db 13, 10, 'last error status: $'
msg_res:    db 13, 10, 'results 0564h: $'
msg_ms:     db ' ms$'
msg_nl:     db 13, 10, '$'

old8:       dd 0
oldimr:     db 0
last:       dw 0
ticks:      dw 0
maxgap:     dw 0
idlegap:    dw 0
readgap:    dw 0
elapsed:    dw 0
t0:         dw 0
errors:     dw 0
laststat:   db 0
bufp:       dw buf1
align 16
buf1:       times 2000h db 0
buf2:       times 2000h db 0
