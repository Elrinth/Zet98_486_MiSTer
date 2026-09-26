; SPDX-License-Identifier: GPL-3.0-or-later
; Standalone XMS resize test. No game code; reproduces small-block growth
; while the caller has interrupts disabled, as used by DOS extenders.
bits 16
cpu 386
org 100h
start:
    push cs
    pop ds
    cld
    mov dx,banner
    call puts
    mov ax,4300h
    int 2fh
    cmp al,80h
    jne fail
    mov ax,4310h
    int 2fh
    mov [entry],bx
    mov [entry+2],es
%ifdef XMS_TRACE_INCLUDE
    call trace_install
%endif
    mov dx,alloc_msg
    call puts
    mov dx,19
    mov ah,9
    call xms
    cmp ax,1
    jne fail
    mov [handle],dx
    mov dx,lock_msg
    call puts
    call lock_unlock
%ifdef XMS_DUMP_DRIVER
    call dump_driver
    jmp park
%endif
%ifdef XMS_COPY_ONLY
    mov dx,second_msg
    call puts
    mov dx,35
    mov ah,9
    call xms
    cmp ax,1
    jne fail
    mov [second_handle],dx
%ifdef XMS_FIRST_HIGH_COPY
    mov dx,first_high_msg
    call puts
    mov dword [transfer],19*1024
    mov ax,[handle]
    mov [transfer+4],ax
    mov dword [transfer+6],0
    mov ax,[second_handle]
    mov [transfer+10],ax
    mov si,transfer
    mov ah,0bh
    call xms
    cmp ax,1
    jne fail
    mov dx,first_high_pass
    call puts
    mov dword [transfer],512
    mov word [transfer+4],0
    mov word [transfer+6],source
%endif
    jmp copy_test
%endif
    mov word [wanted],35
grow:
    mov dx,resize_msg
    call puts
    mov ax,[wanted]
    call hex16
    mov dx,newline
    call puts
    mov dx,[handle]
    mov bx,[wanted]
    mov ah,0fh
    call xms
    cmp ax,1
    jne fail
    call lock_unlock
    add word [wanted],16
    cmp word [wanted],147
    jb grow
copy_test:
    mov dx,move_msg
    call puts
    mov di,source
    xor cx,cx
.fill:
    mov ax,cx
    xor ax,55aah
    mov [di],ax
    add di,2
    inc cx
    cmp cx,256
    jb .fill
    mov ax,cs
    mov [transfer+8],ax
    mov ax,[handle]
    mov [transfer+10],ax
    mov si,transfer
    mov ah,0bh
    call xms
    cmp ax,1
    jne fail
%ifdef XMS_COPY_ONLY
    mov dx,high_copy_msg
    call puts
    mov dword [transfer],19*1024
    mov ax,[handle]
    mov [transfer+4],ax
    mov dword [transfer+6],0
    mov ax,[second_handle]
    mov [transfer+10],ax
    mov si,transfer
    mov ah,0bh
    call xms
    cmp ax,1
    jne fail
    mov dword [transfer],512
    mov dx,readback_msg
    call puts
    mov ax,[second_handle]
%else
    mov ax,[handle]
%endif
    mov [transfer+4],ax
    mov dword [transfer+6],0
    mov word [transfer+10],0
    mov word [transfer+12],dest
    mov ax,cs
    mov [transfer+14],ax
    mov si,transfer
    mov ah,0bh
    call xms
    cmp ax,1
    jne fail
%ifdef XMS_COPY_ONLY
    mov dx,[second_handle]
    mov ah,0ah
    call xms
    cmp ax,1
    jne fail
%endif
    push cs
    pop es
    cld
    mov si,source
    mov di,dest
    mov cx,256
    repe cmpsw
    jne fail
    mov dx,[handle]
    mov ah,0ah
    call xms
    cmp ax,1
    jne fail
    mov dx,pass_msg
    call puts
park:
    sti
    hlt
    jmp park
lock_unlock:
    mov dx,[handle]
    mov ah,0ch
    call xms
    cmp ax,1
    jne fail
    push bx
    mov ax,dx
    call hex16
    pop ax
    call hex16
    mov dx,newline
    call puts
    mov dx,[handle]
    mov ah,0dh
    call xms
    cmp ax,1
    jne fail
    ret
xms:
    pushf
    cli
    call far [cs:entry]
    popf
    ret
puts:
    mov ah,9
    int 21h
    ret
hex16:
    push ax
    push bx
    push cx
    push dx
    mov bx,ax
    mov cx,4
.digit:
    rol bx,4
    mov dl,bl
    and dl,15
    add dl,'0'
    cmp dl,'9'
    jbe .out
    add dl,7
.out:
    mov ah,2
    int 21h
    loop .digit
    pop dx
    pop cx
    pop bx
    pop ax
    ret
fail:
    push ax
    mov dx,fail_msg
    call puts
    pop ax
    call hex16
    mov dx,newline
    call puts
    jmp park
entry: dd 0
handle: dw 0
second_handle: dw 0
wanted: dw 0
transfer: dd 512
    dw 0
    dw source,0
    dw 0
    dd 0
%ifdef XMS_COPY_ONLY
banner: db 'Zet98 XMS separate allocation/copy: IF=0',13,10,'$'
%else
banner: db 'Zet98 XMS resize control: caller IF=0',13,10,'$'
%endif
alloc_msg: db 'Allocate 19 KB',13,10,'$'
lock_msg: db 'Lock/unlock: ', '$'
resize_msg: db 'Resize KB(hex): $'
move_msg: db 'Verify 512-byte XMS copy round trip',13,10,'$'
%ifdef XMS_COPY_ONLY
pass_msg: db 'PASS: allocations and extended-to-extended copy',13,10,'$'
%else
pass_msg: db 'PASS: 7 resizes, locks, unlocks and data copy',13,10,'$'
%endif
second_msg: db 'Allocate separate 35 KB block',13,10,'$'
high_copy_msg: db 'Copy 19 KB: extended to extended',13,10,'$'
readback_msg: db 'Read back 512 bytes',13,10,'$'
%ifdef XMS_FIRST_HIGH_COPY
first_high_msg: db 'FIRST copy: extended to extended 19 KB',13,10,'$'
first_high_pass: db 'First extended copy returned',13,10,'$'
%endif
fail_msg: db 'FAIL AX=$'
newline: db 13,10,'$'
source: times 512 db 0
dest: times 512 db 0
%ifdef XMS_DUMP_DRIVER
dump_driver:
    mov dx,dump_name
    xor cx,cx
    mov ah,5bh
    int 21h
    jc fail
    mov bx,ax
    push ds
    mov ds,[entry+2]
    xor dx,dx
    mov cx,4096
    mov ah,40h
    int 21h
    pop ds
    jc fail
    cmp ax,4096
    jne fail
    mov ah,3eh
    int 21h
    jc fail
    mov dx,dump_message
    call puts
    ret
dump_name: db 'HIMEDMP.BIN',0
dump_message: db 'Resident driver snapshot saved to HIMEDMP.BIN',13,10,'$'
%endif
%ifdef XMS_TRACE_INCLUDE
%include XMS_TRACE_INCLUDE
%endif
