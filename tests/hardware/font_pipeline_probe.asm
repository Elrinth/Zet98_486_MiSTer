; SPDX-License-Identifier: GPL-3.0-or-later
; Combined CG-ROM -> upper RAM -> glyph expansion -> GRCG diagnostic.
; Synthetic code and lookup table; private font bytes appear only in capture.
; Disposable DOS shell, native banking, no memory managers. Changes VRAM.
bits 16
cpu 8086
org 100h
CAPTURE equ 1000h
RECORD_BYTES equ 958
RECORD_COUNT equ 56
CAPTURE_BYTES equ 16+RECORD_COUNT*RECORD_BYTES
RAW equ 4a04h
EXPANDED equ 49a4h
SHIFTED equ 49e4h
LOOKUP equ 57b3h
KCODE equ 6000h
OUTPUT equ 7000h

start:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,0fffeh
    mov ds,ax
    mov es,ax
    sti
    cld
    cmp ax,5000h
    ja unsafe_memory
    cmp word [2],0a000h
    jb unsafe_memory
    mov si,header
    mov di,CAPTURE
    mov cx,16
    rep movsb
    mov ax,cs
    mov [CAPTURE+8],ax
    mov ax,[2]
    mov [CAPTURE+10],ax
    in al,0a6h
    and al,1
    mov [saved_page],al
    xor al,al
    out 0a6h,al
    mov al,1
    out 6ah,al
    mov word [capture_pos],CAPTURE+16
    mov word [test_segment],7000h
.segment:
    mov es,[test_segment]
    mov di,400h
    mov si,kernel
    mov cx,kernel_end-kernel
    rep movsb
    mov di,LOOKUP
    mov si,lookup
    mov cx,512
    rep movsb
    mov byte [interrupt_mode],0
.mode:
    mov word [glyph_index],0
.glyph:
    mov bx,[glyph_index]
    shl bx,1
    mov ax,[codes+bx]
    mov dx,[test_segment]
    mov [kernel_ptr+2],dx
    pushf
    cmp byte [interrupt_mode],0
    jne .enable
    cli
    jmp .invoke
.enable:
    sti
.invoke:
    call far [kernel_ptr]
    popf
    push cs
    pop es
    mov di,[capture_pos]
    mov ax,[test_segment]
    stosw
    mov bx,[glyph_index]
    shl bx,1
    mov ax,[codes+bx]
    stosw
    mov al,[interrupt_mode]
    stosb
    xor al,al
    stosb
    push ds
    mov ds,[test_segment]
    mov si,OUTPUT
    mov cx,RECORD_BYTES-6
    rep movsb
    pop ds
    mov [capture_pos],di
    inc word [glyph_index]
    cmp word [glyph_index],14
    jb .glyph
    inc byte [interrupt_mode]
    cmp byte [interrupt_mode],2
    jb .mode
    cmp word [test_segment],7000h
    jne .done
    mov word [test_segment],8bdeh
    jmp .segment
.done:
    mov al,[saved_page]
    out 0a6h,al
    cmp word [capture_pos],CAPTURE+CAPTURE_BYTES
    jne failed
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,filename
    mov ax,5b00h
    xor cx,cx
    int 21h
    jc failed
    mov bx,ax
    mov dx,CAPTURE
    mov cx,CAPTURE_BYTES
    mov ah,40h
    int 21h
    jc close_failed
    cmp ax,CAPTURE_BYTES
    jne close_failed
    mov ah,3eh
    int 21h
    jc failed
    mov ah,0dh
    int 21h
    mov dx,success_text
    xor al,al
    jmp print_result
close_failed:
    mov ah,3eh
    int 21h
failed:
    mov dx,failure_text
    mov al,1
    jmp print_result
unsafe_memory:
    mov dx,unsafe_text
    mov al,1
print_result:
    push ax
    mov ah,9
    int 21h
    pop ax
%ifdef PROBE_SHELL
    sti
.halt:
    hlt
    jmp .halt
%else
    mov ah,4ch
    int 21h
%endif
critical_error:
    mov al,3
    iret

; Relative branches/calls and fixed data offsets permit relocation to either
; segment. Raw data intentionally overlaps the later SHIFTED output, as in
; the rendering sequence under investigation; snapshot each stage in time.
kernel:
    push ds
    push es
    mov [cs:KCODE],ax
    push cs
    pop ds
    push cs
    pop es
    mov al,0bh
    out 68h,al
    mov ax,[KCODE]
    xchg al,ah
    out 0a1h,al
    mov al,ah
    out 0a3h,al
    mov di,RAW
    mov cx,16
    mov bl,20h
.font_row:
    mov al,bl
    out 0a5h,al
    in al,0a9h
    mov [di],al
    inc di
    xor bl,20h
    mov al,bl
    out 0a5h,al
    in al,0a9h
    mov [di],al
    xor bl,20h
    inc di
    inc bl
    loop .font_row
    mov al,0ah
    out 68h,al
    mov si,RAW
    mov di,OUTPUT
    mov cx,32
    rep movsb
    mov si,RAW
    mov di,EXPANDED
    mov cx,32
.expand:
    xor ah,ah
    lodsb
    mov bx,LOOKUP
    shl ax,1
    add bx,ax
    mov ax,[cs:bx]
    stosw
    loop .expand
    mov si,EXPANDED
    mov di,OUTPUT+32
    mov cx,64
    rep movsb
    mov si,EXPANDED
    mov di,SHIFTED
    mov cx,16
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
    mov si,SHIFTED
    mov di,OUTPUT+96
    mov cx,64
    rep movsb
    ; Seed six bytes per row: one untouched byte on each side of the draw.
    xor al,al
    out 7ch,al
    xor bx,bx
.seed_plane:
    call plane_segment
    mov es,ax
    mov ax,bx
    mov cl,6
    shl ax,cl
    sub al,bl
    sub al,bl
    sub al,bl
    add al,3                    ; plane seeds 3,64,125,186
    mov di,100h
    mov dx,33
.seed_row:
    mov cx,6
    rep stosb
    add di,74
    dec dx
    jnz .seed_row
    inc bx
    cmp bx,4
    jb .seed_plane
    mov ax,0a800h
    mov es,ax
    mov al,0c0h
    out 7ch,al
    xor al,al
    out 7eh,al
    nop
    out 7eh,al
    nop
    out 7eh,al
    nop
    out 7eh,al
    nop
    mov si,EXPANDED
    mov di,151h                 ; black shadow one scanline down
    call draw
    xor al,al
    out 7ch,al
    mov al,0c0h
    out 7ch,al
    mov al,0ffh
    out 7eh,al
    out 7eh,al
    out 7eh,al
    out 7eh,al
    mov si,SHIFTED
    mov di,101h                 ; shifted foreground; deliberately odd words
    call draw
    xor al,al
    out 7ch,al
    push cs
    pop es
    mov di,OUTPUT+160
    xor bx,bx
.capture_plane:
    call plane_segment
    mov ds,ax
    mov si,100h
    mov dx,33
.capture_row:
    mov cx,6
    rep movsb
    add si,74
    dec dx
    jnz .capture_row
    inc bx
    cmp bx,4
    jb .capture_plane
    pop es
    pop ds
    retf

draw:
    mov cx,2
    mov dx,16
.row:
    push di
    push cx
    push si
    rep movsw
    pop si
    pop cx
    pop di
    add di,80
    push di
    push cx
    rep movsw
    pop cx
    pop di
    add di,80
    dec dx
    jnz .row
    ret
plane_segment:
    mov ax,0e000h
    cmp bx,3
    je .done
    mov ax,bx
    mov cl,11
    shl ax,cl
    add ax,0a800h
.done:
    ret
kernel_end:

test_segment: dw 0
glyph_index: dw 0
interrupt_mode: db 0
saved_page: db 0
capture_pos: dw 0
kernel_ptr: dw 400h,0
codes: dw 2009h,5309h,7409h,6109h,7209h,4309h,6f09h
       dw 6e09h,6909h,7509h,6509h,4f09h,7009h,7309h
header: db 'Z98PIPE1'
    dw 0,0,RECORD_COUNT,RECORD_BYTES
filename: db 'Z98PIPE.BIN',0
success_text: db 'Font pipeline saved to Z98PIPE.BIN.',13,10,'$'
failure_text: db 'Cannot create/write NEW Z98PIPE.BIN.',13,10,'$'
unsafe_text: db 'Pipeline refused: RAM allocation is unsafe.',13,10,'$'
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
%if ($-$$+100h)>CAPTURE
    %error Code overlaps capture
%endif
%if CAPTURE+CAPTURE_BYTES>0f000h
    %error Capture overlaps stack reserve
%endif
%if 400h+(kernel_end-kernel)>=EXPANDED
    %error Relocated kernel overlaps data
%endif
