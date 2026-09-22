; SPDX-License-Identifier: GPL-3.0-or-later
; Synthetic GRCG/VRAM diagnostic for a disposable DOS shell without managers.
; Changes both graphics pages, enables 16 colors, restores CPU page on exit.
bits 16
cpu 8086
org 100h
CAPTURE equ 2000h
RECORDS equ 32
CAPTURE_BYTES equ 16+RECORDS*(4+4*256)
start:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,0fffeh
    mov ds,ax
    mov es,ax
    sti
    cld
    cmp ax,6000h
    ja unsafe_memory
    cmp word [2],9100h
    jb unsafe_memory
    mov si,header
    mov di,CAPTURE
    mov cx,16
    rep movsb
    mov ax,cs
    mov [CAPTURE+8],ax
    mov ax,[2]
    mov [CAPTURE+10],ax
    mov dx,461h
    in al,dx
    mov [CAPTURE+12],al
    add dx,2
    in al,dx
    mov [CAPTURE+13],al
    mov word [capture_pos],CAPTURE+16
    mov ax,9000h
    mov es,ax
    mov di,100h
    mov si,masks
    mov cx,256
    rep movsb
    in al,0a6h
    and al,1
    mov [saved_page],al
    pushf
    cli
    mov al,1
    out 6ah,al                   ; 16-color graphics access (plane E000h)
    mov byte [source_case],0
.source:
    mov byte [page],0
.page:
    mov al,[page]
    out 0a6h,al
    call seed_planes
    mov byte [phase],0
    call capture_planes

    call rmw_tiles
    push ds
    xor bx,bx
    call select_source
    mov di,110h
    mov cx,32                    ; 64 aligned mask bytes
    rep movsw
    pop ds
    inc byte [phase]
    call capture_planes

    call rmw_tiles
    push ds
    mov bx,64
    call select_source
    mov di,151h
    mov cx,16                    ; 32 mask bytes, odd destination words
    rep movsw
    pop ds
    inc byte [phase]
    call capture_planes

    call rmw_tiles
    push ds
    mov bx,96
    call select_source
    mov di,180h
    mov cx,32
    rep movsb
    pop ds
    inc byte [phase]
    call capture_planes

    call rmw_tiles
    push ds
    mov bx,128
    call select_source
    mov di,1b1h
    mov cx,16                    ; preserve every adjacent even byte
.sparse:
    movsb
    inc di
    loop .sparse
    pop ds
    inc byte [phase]
    call capture_planes

    mov al,85h                   ; TDW, planes 0 and 2 disabled
    mov bx,tdw_pattern
    call program_tiles
    push ds
    mov bx,144
    call select_source
    mov di,1d1h
    mov cx,8                     ; source ignored, destination lanes retained
    rep movsw
    pop ds
    inc byte [phase]
    call capture_planes

    call rmw_tiles
    push ds
    mov bx,160
    call select_source
    mov di,100h
    mov dx,2                     ; two source rows, each doubled vertically
.row:
    push di
    push si
    mov cx,2
    rep movsw
    pop si
    pop di
    add di,80
    push di
    mov cx,2
    rep movsw
    pop di
    add di,80
    dec dx
    jnz .row
    pop ds
    inc byte [phase]
    call capture_planes
    inc byte [page]
    cmp byte [page],2
    jb .page
    ; Revisit both pages after writing the other page: detects page aliasing.
    mov byte [phase],7
    mov byte [page],0
.revisit:
    mov al,[page]
    out 0a6h,al
    call capture_planes
    inc byte [page]
    cmp byte [page],2
    jb .revisit
    inc byte [source_case]
    cmp byte [source_case],2
    jb .source
    xor al,al
    out 7ch,al
    mov al,[saved_page]
    out 0a6h,al
    popf
    push cs
    pop es
    cmp word [capture_pos],CAPTURE+CAPTURE_BYTES
    jne failed
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,filename
    mov ax,5b00h                 ; exclusive create, never replace a capture
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

seed_planes:
    xor al,al
    out 7ch,al
    xor bx,bx
.plane:
    mov ax,[planes+bx]
    mov es,ax
    mov si,bx
    shr si,1
    mov al,[seeds+si]
    cmp byte [page],0
    je .no_page
    add al,29
.no_page:
    cmp byte [source_case],0
    je .no_source
    add al,7
.no_source:
    mov di,100h
    mov cx,256
.fill:
    stosb
    add al,17
    loop .fill
    add bx,2
    cmp bx,8
    jb .plane
    ret

rmw_tiles:
    mov al,0c0h
    mov bx,rmw_pattern
program_tiles:
    out 7ch,al
    mov cx,4
.tile:
    mov al,[bx]
    out 7eh,al
    inc bx
    loop .tile
    mov ax,0a800h
    mov es,ax
    ret

; Input BX is a byte offset. Caller saves/restores DS.
select_source:
    cmp byte [cs:source_case],0
    jne .upper
    push cs
    pop ds
    mov si,masks
    jmp .offset
.upper:
    mov ax,9000h
    mov ds,ax
    mov si,100h
.offset:
    add si,bx
    ret

capture_planes:
    xor al,al
    out 7ch,al                   ; read actual plane data, not tile-compare data
    push ds
    push es
    push cs
    pop es
    mov di,[capture_pos]
    mov al,[source_case]
    stosb
    mov al,[page]
    stosb
    mov al,[phase]
    stosb
    xor al,al
    stosb
    xor bx,bx
.plane:
    mov ax,[cs:planes+bx]
    mov ds,ax
    mov si,100h
    mov cx,256
    rep movsb
    add bx,2
    cmp bx,8
    jb .plane
    pop es
    pop ds
    mov [capture_pos],di
    ret

source_case: db 0
page: db 0
phase: db 0
saved_page: db 0
capture_pos: dw 0
planes: dw 0a800h,0b000h,0b800h,0e000h
seeds: db 3,64,125,186
rmw_pattern: db 3ch,0a5h,5ah,0c3h
tdw_pattern: db 0f0h,0fh,69h,96h
header: db 'Z98GRCG1'
    dw 0,0
    db 0,0
    dw RECORDS
filename: db 'Z98GRCG.BIN',0
success_text: db 'GRCG/VRAM capture saved to Z98GRCG.BIN.',13,10,'$'
failure_text: db 'Cannot create/write NEW Z98GRCG.BIN.',13,10,'$'
unsafe_text: db 'Probe refused: RAM allocation is unsafe.',13,10,'$'
masks:
%assign i 0
%rep 256
    db (i*73+19) & 255
%assign i i+1
%endrep
%if ($-$$+100h)>CAPTURE
    %error Code overlaps runtime capture buffer
%endif
%if CAPTURE+CAPTURE_BYTES>0f000h
    %error Capture overlaps stack reserve
%endif
