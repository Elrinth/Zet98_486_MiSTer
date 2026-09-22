; SPDX-License-Identifier: GPL-3.0-or-later
; Disposable DOS probe: RMW through every addressed plane, with word/byte
; accesses and neighbouring guard bytes. Changes 8 off-screen bytes per plane.
bits 16
cpu 8086
org 100h
CAPTURE equ 2000h
RECORDS equ 2*16*4*4
CAPTURE_BYTES equ 16+RECORDS*36
start:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,0fffeh
    mov ds,ax
    mov es,ax
    sti
    cld
    add ax,1000h
    jc failed
    cmp [2],ax
    jb failed
    mov si,header
    mov di,CAPTURE
    mov cx,16
    rep movsb
    mov word [capture_pos],CAPTURE+16
    in al,0a6h
    and al,1
    mov [saved_page],al
    pushf
    cli
    mov al,1
    out 6ah,al
    mov byte [page],0
.page:
    mov al,[page]
    out 0a6h,al
    mov byte [disabled],0
.mask:
    mov byte [alias_plane],0
.alias:
    mov byte [access],0
.access:
    call seed_planes
    mov al,[disabled]
    or al,0c0h
    out 7ch,al
    mov si,tiles
    mov cx,4
.tiles:
    lodsb
    out 7eh,al
    loop .tiles
    xor bx,bx
    mov bl,[alias_plane]
    shl bx,1
    mov ax,[segments+bx]
    mov es,ax
    mov al,[access]
    cmp al,0
    jne .not_word
    mov word [es:7f02h],0a55ah
    jmp .capture
.not_word:
    cmp al,1
    jne .not_even
    mov byte [es:7f02h],5ah
    jmp .capture
.not_even:
    cmp al,2
    jne .odd_word
    mov byte [es:7f03h],0a5h
    jmp .capture
.odd_word:
    mov word [es:7f03h],3cc3h
.capture:
    call capture_planes
    inc byte [access]
    cmp byte [access],4
    jb .access
    inc byte [alias_plane]
    cmp byte [alias_plane],4
    jb .alias
    inc byte [disabled]
    cmp byte [disabled],16
    jb .mask
    inc byte [page]
    cmp byte [page],2
    jb .page
    xor al,al
    out 7ch,al
    mov al,[saved_page]
    out 0a6h,al
    popf
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
    mov dl,3
.plane:
    mov ax,[segments+bx]
    mov es,ax
    mov al,dl
    cmp byte [page],0
    je .fill_start
    add al,29
.fill_start:
    mov di,7f00h
    mov cx,8
.fill:
    stosb
    add al,73
    loop .fill
    add dl,61
    add bx,2
    cmp bx,8
    jb .plane
    ret
capture_planes:
    xor al,al
    out 7ch,al
    push ds
    push es
    push cs
    pop es
    mov di,[capture_pos]
    mov al,[page]
    stosb
    mov al,[disabled]
    stosb
    mov al,[alias_plane]
    stosb
    mov al,[access]
    stosb
    xor bx,bx
.plane:
    mov ax,[cs:segments+bx]
    mov ds,ax
    mov si,7f00h
    mov cx,8
    rep movsb
    add bx,2
    cmp bx,8
    jb .plane
    pop es
    pop ds
    mov [capture_pos],di
    ret
page: db 0
disabled: db 0
alias_plane: db 0
access: db 0
saved_page: db 0
capture_pos: dw 0
segments: dw 0a800h,0b000h,0b800h,0e000h
tiles: db 3ch,0a5h,5ah,0c3h
header: db 'Z98GAL1',0
    dw RECORDS
    times 6 db 0
filename: db 'Z98GAL.BIN',0
success_text: db 'GRCG plane-alias capture saved to Z98GAL.BIN.',13,10,'$'
failure_text: db 'GRCG plane-alias capture FAILED.',13,10,'$'
%if ($-$$+100h)>CAPTURE
    %error Code overlaps capture buffer
%endif
%if CAPTURE+CAPTURE_BYTES>0f000h
    %error Capture overlaps stack reserve
%endif
