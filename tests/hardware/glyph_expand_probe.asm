; SPDX-License-Identifier: GPL-3.0-or-later
; Synthetic pixel expansion and carry-chain diagnostic; no game/ROM data.
; Run as the shell of a disposable DOS floppy without memory managers.
bits 16
cpu 8086
org 100h
start:
    push cs
    pop ds
    cld
    mov ax,cs
    mov [capture_cs],ax
    cmp ax,6000h                 ; program and stack stay below 70000h
    ja unsafe_memory
    mov ax,[2]
    mov [capture_end],ax
    cmp ax,9300h                 ; includes upper test buffers through 927ffh
    jb unsafe_memory
    mov dx,461h
    in al,dx
    mov [bank89],al
    add dx,2
    in al,dx
    mov [bankab],al
    mov word [capture_pos],records
    mov bp,7000h
.segment:
    mov es,bp
    xor di,di
    mov si,kernel
    mov cx,kernel_end-kernel
    rep movsb
    mov di,1000h
    mov si,pattern
    mov cx,512
    rep movsb
    mov di,1593h                 ; deliberately odd word lookup addresses
    mov si,lookup
    mov cx,512
    rep movsb
    mov [kernel_ptr+2],bp
    pushf
    cli
    call far [kernel_ptr]
    popf
    mov di,[capture_pos]
    mov [di],bp
    add di,2
    push ds
    mov ds,bp
    push cs
    pop es
    mov si,2000h
    mov cx,2048                  ; expanded pixels followed by shifted pixels
    rep movsb
    pop ds
    mov [capture_pos],di
    add bp,2000h
    cmp bp,0b000h
    jb .segment
    push cs
    pop es
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,filename
    mov ax,5b00h                 ; create only; never replace an older result
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

; Position-independent code copied to both a low and an upper RAM segment.
kernel:
    push ds
    push es
    push cs
    pop ds
    push cs
    pop es
    mov si,1000h
    mov di,2000h
    mov cx,512
.expand:
    xor ah,ah
    lodsb
    mov bx,1593h
    shl ax,1
    add bx,ax
    mov ax,[cs:bx]
    stosw
    loop .expand
    mov si,2000h
    mov di,2400h
    mov cx,256
.shift:
    lodsw
    mov dx,ax
    lodsw
    shl ah,1
    rcl al,1
    rcl dh,1
    rcl dl,1
    mov [cs:di],dx
    mov [cs:di+2],ax
    add di,4
    loop .shift
    pop es
    pop ds
    retf
kernel_end:

kernel_ptr: dw 0,0
capture_pos: dw 0
filename: db 'Z98GLYF.BIN',0
success_text: db 'Glyph arithmetic saved to Z98GLYF.BIN.',13,10,'$'
failure_text: db 'Cannot create/write NEW Z98GLYF.BIN.',13,10,'$'
unsafe_text: db 'Probe refused: test RAM is not owned by this process.',13,10,'$'
pattern:
%assign i 0
%rep 256
    db i, i ^ 0a5h
%assign i i+1
%endrep
lookup:
%assign i 0
%rep 256
%assign expanded 0
%assign bit 0
%rep 8
%if i & (1 << bit)
%assign expanded expanded | (3 << (2*bit))
%endif
%assign bit bit+1
%endrep
    dw ((expanded & 255) << 8) | (expanded >> 8)
%assign i i+1
%endrep
capture:
    db 'Z98GLYF1'
capture_cs: dw 0
capture_end: dw 0
bank89: db 0
bankab: db 0
    dw 2
records: times 2*(2+2048) db 0
capture_end_data:
