; SPDX-License-Identifier: GPL-3.0-or-later
; DOS shell diagnostic after Z98MEM.SYS and HIMEMX(98), on a disposable disk.
bits 16
cpu 486
org 100h
%ifndef TOP_MB
%define TOP_MB 64
%endif
%if TOP_MB = 64
%define ALLOC_KB 17408
%define MIN_KB 60000
%else
%define ALLOC_KB 1024
%define MIN_KB 13000
%endif
start:
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0fffeh
    cld
    mov dx, critical_error
    mov ax, 2524h
    int 21h
    mov ax, 4300h
    int 2fh
    cmp al, 80h
    jne fail
    mov ax, 4310h
    int 2fh
    mov [entry], bx
    mov [entry+2], es
    mov ah, 88h
    call far [entry]
    cmp edx, MIN_KB
    jb fail
    mov [free_kb], edx
    mov edx, ALLOC_KB
    mov ah, 89h
    call far [entry]
    cmp ax, 1
    jne fail
    mov [handle], dx
    mov ah, 0ch
    call far [entry]
    cmp ax, 1
    jne fail
    movzx eax, dx
    shl eax, 16
    mov ax, bx
    mov [block_address], eax
%if TOP_MB = 64
    cmp dx, 100h                  ; 17 MB block must live above the 15-16 MB hole
    jb fail
%endif
    mov dx, [handle]
    mov ah, 0dh
    call far [entry]
    cmp ax, 1
    jne fail
    push cs
    pop es
    mov di, source
    mov cx, 256
    mov ax, 0a598h
.pattern:
    stosw
    add ax, 0391h
    loop .pattern
    mov word [far_source], source
    mov [far_source+2], cs
    mov word [far_dest], destination
    mov [far_dest+2], cs
    mov dword [offset], 0
    call roundtrip
    mov dword [offset], ALLOC_KB*1024-512
    call roundtrip
    mov dx, [handle]
    mov ah, 0ah
    call far [entry]
    cmp ax, 1
    jne fail
    mov ah, 88h
    call far [entry]
    cmp edx, [free_kb]
    jne fail
    mov eax, [free_kb]
    mov di, free_hex
    call hex8
    mov eax, [block_address]
    mov di, address_hex
    call hex8
    mov si, pass_text
    jmp report
roundtrip:
    push cs
    pop es
    mov di, destination
    mov cx, 256
    mov ax, 0deadH
    rep stosw
    xor word [source], 1234h
    mov word [move_src_handle], 0
    mov eax, [far_source]
    mov [move_src_offset], eax
    mov ax, [handle]
    mov [move_dst_handle], ax
    mov eax, [offset]
    mov [move_dst_offset], eax
    call transfer
    mov ax, [handle]
    mov [move_src_handle], ax
    mov eax, [offset]
    mov [move_src_offset], eax
    mov word [move_dst_handle], 0
    mov eax, [far_dest]
    mov [move_dst_offset], eax
    call transfer
    push cs
    pop es
    mov si, source
    mov di, destination
    mov cx, 256
    repe cmpsw
    jne fail
    ret
transfer:
    mov si, move
    mov ah, 0bh
    call far [entry]
    cmp ax, 1
    jne fail
    ret
hex8:
    mov cx, 8
.digit:
    rol eax, 4
    mov bl, al
    and bl, 15
    add bl, '0'
    cmp bl, '9'
    jbe .store
    add bl, 7
.store:
    mov [di], bl
    inc di
    loop .digit
    ret
fail:
    mov si, fail_text
report:
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
    mov ah, 3eh
    int 21h
    mov ah, 0dh
    int 21h
halt:
    sti
    hlt
    jmp halt
critical_error:
    mov al, 3
    iret
entry: dd 0
handle: dw 0
free_kb: dd 0
block_address: dd 0
offset: dd 0
far_source: dd 0
far_dest: dd 0
move: dd 512
move_src_handle: dw 0
move_src_offset: dd 0
move_dst_handle: dw 0
move_dst_offset: dd 0
message: dw 0
length: dw 0
log_name: db 'Z98XMS.TXT',0
pass_text: db 13,10,'PASS: HIMEMX(98) detected extended RAM, allocated/locked a block,',13,10
    db 'copied and verified both ends, unlocked/freed it and recovered free RAM.',13,10
%if TOP_MB = 64
    db '64 MB map: >=60000 KB free; 17 MB allocation above 16 MB.',13,10
%else
    db '16 MB map: >=13000 KB free; 1 MB allocation.',13,10
%endif
    db 'Hex free KB='
free_hex: db '00000000; block physical address='
address_hex: db '00000000',13,10,0
fail_text: db 13,10,'FAIL: XMS discovery/allocation/move/free check.',13,10,0
source: times 512 db 0
destination: times 512 db 0
times 0 * (1 / (($ - $$) <= 2011)) db 0
