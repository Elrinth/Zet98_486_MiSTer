; SPDX-License-Identifier: GPL-3.0-or-later
; Disposable DOS diagnostic. Changes 34 off-screen bytes in each VRAM plane
; of both pages; enables 16-color access and restores the CPU page on exit.
bits 16
cpu 8086
org 100h
CAPTURE equ 2000h
RECORDS equ 2*16*4*16
CAPTURE_BYTES equ 16+RECORDS*10
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
    call seed_planes
    mov byte [disabled],0
.mask:
    mov al,[disabled]
    or al,80h
    out 7ch,al
    mov si,tiles
    mov cx,4
.tiles:
    lodsb
    out 7eh,al
    loop .tiles
    mov byte [alias_plane],0
.alias:
    xor bx,bx
    mov bl,[alias_plane]
    shl bx,1
    mov ax,[segments+bx]
    mov es,ax
    xor bx,bx
.word:
    mov di,[capture_pos]
    mov al,[page]
    mov [di],al
    mov al,[disabled]
    mov [di+1],al
    mov al,[alias_plane]
    mov [di+2],al
    mov ax,bx
    shr ax,1
    mov [di+3],al
    mov ax,[es:bx+7f00h]
    mov [di+4],ax
    mov ax,[es:bx+7f01h]
    mov [di+6],ax
    mov al,[es:bx+7f00h]
    mov [di+8],al
    mov al,[es:bx+7f01h]
    mov [di+9],al
    add word [capture_pos],10
    add bx,2
    cmp bx,32
    jb .word
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
    mov cx,34
.fill:
    stosb
    add al,73
    loop .fill
    add dl,61
    add bx,2
    cmp bx,8
    jb .plane
    ret
page: db 0
disabled: db 0
alias_plane: db 0
saved_page: db 0
capture_pos: dw 0
segments: dw 0a800h,0b000h,0b800h,0e000h
tiles: db 3ch,0a5h,5ah,0c3h
header: db 'Z98GCMP1'
    dw RECORDS
    times 6 db 0
filename: db 'Z98GCMP.BIN',0
success_text: db 'GRCG comparison saved to Z98GCMP.BIN.',13,10,'$'
failure_text: db 'GRCG comparison capture FAILED.',13,10,'$'
%if ($-$$+100h)>CAPTURE
    %error Code overlaps capture buffer
%endif
%if CAPTURE+CAPTURE_BYTES>0f000h
    %error Capture overlaps stack reserve
%endif
