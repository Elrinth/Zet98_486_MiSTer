; SPDX-License-Identifier: GPL-3.0-or-later
; Run as the shell of a disposable DOS floppy without memory managers.
; Tests only conventional RAM owned by this COM process. Original media is
; untouched; the result file is created only if its name does not exist.
bits 16
cpu 8086
org 100h
start:
    push cs
    pop ds
    cld
    mov ax,cs
    mov [capture_cs],ax
    ; Keep both the program and its default 64-KiB stack segment below 70000h.
    cmp ax,6000h
    ja unsafe_memory
    mov ax,[2]                  ; PSP end of this process's allocation
    mov [capture_end],ax
    cmp ax,9100h
    jb unsafe_memory
    mov dx,461h
    in al,dx
    mov [bank89],al
    add dx,2
    in al,dx
    mov [bankab],al
    mov di,records
    mov bp,7000h
.segment:
    mov [di],bp
    add di,2
    mov es,bp
    pushf
    cli
    mov si,pattern
    xor bx,bx
    mov cx,1026
.fill:
    mov al,[si]
    mov [es:bx],al              ; independent byte writes, like Rusty's buffer
    inc si
    inc bx
    loop .fill
    xor bx,bx
    mov cx,1024
.read_bytes:
    mov al,[es:bx]
    mov [di],al
    inc di
    inc bx
    loop .read_bytes
    xor bx,bx
    mov cx,512
.read_aligned:
    mov ax,[es:bx]
    mov [di],ax
    add bx,2
    add di,2
    loop .read_aligned
    mov bx,1
    mov cx,512
.read_odd:
    mov ax,[es:bx]              ; odd word reads, including cache-line crossings
    mov [di],ax
    add bx,2
    add di,2
    loop .read_odd
    mov word [es:100h],0a55ah
    mov byte [es:100h],0c3h
    mov ax,[es:100h]
    mov [di],ax
    mov byte [es:101h],3ch
    mov ax,[es:100h]
    mov [di+2],ax
    mov word [es:11fh],96e1h
    mov ax,[es:11fh]
    mov [di+4],ax
    mov byte [es:120h],69h
    mov ax,[es:11fh]
    mov [di+6],ax
    add di,8
    popf
    add bp,1000h
    cmp bp,0a000h
    jb .segment
    push cs
    pop es
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,filename
    mov ax,5b00h
    xor cx,cx
    int 21h
    jc failed
    mov bx,ax
    mov dx,capture
    mov cx,capture_end_data-capture
    mov ah,40h
    int 21h
    jc close_failed
    cmp ax,capture_end_data-capture
    jne close_failed
    mov ah,3eh
    int 21h
    jc failed
    mov ah,0dh
    int 21h
    mov dx,success_text
    jmp print_result
close_failed:
    mov ah,3eh
    int 21h
failed:
    mov dx,failure_text
    jmp print_result
unsafe_memory:
    mov dx,unsafe_text
print_result:
    mov ah,9
    int 21h
%ifdef PROBE_SHELL
    sti
.halt:
    hlt
    jmp .halt
%else
    mov ax,4c00h
    int 21h
%endif
critical_error:
    mov al,3
    iret
filename: db 'Z98BYTE.BIN',0
success_text: db 'Conventional RAM capture saved to Z98BYTE.BIN.',13,10,'$'
failure_text: db 'Cannot create/write NEW Z98BYTE.BIN.',13,10,'$'
unsafe_text: db 'Probe refused: test RAM is not owned by this process.',13,10,'$'
pattern:
%assign i 0
%rep 1026
    db ((i*73+19) ^ (i>>8)) & 255
%assign i i+1
%endrep
capture:
    db 'Z98BYTE1'
capture_cs: dw 0
capture_end: dw 0
bank89: db 0
bankab: db 0
    dw 3
records: times 3*(2+3072+8) db 0
capture_end_data:
program_end:
