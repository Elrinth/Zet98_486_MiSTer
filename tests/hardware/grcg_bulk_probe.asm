; SPDX-License-Identifier: GPL-3.0-or-later
; Full 32 KiB VRAM transfers, independently checked by sampled readback.
; Four operations, two pages, four planes; 4096 captured bytes per record.
bits 16
cpu 186
org 100h
BUFFER equ 2000h
start:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,0fffeh
    mov ds,ax
    mov es,ax
    sti
    cld
    add ax,2000h
    jc failed
    cmp [2],ax
    jb failed
    sub ax,1000h
    mov [source_seg],ax
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,filename
    mov ax,5b00h
    xor cx,cx
    int 21h
    jc failed
    mov [handle],ax
    mov dx,header
    mov cx,16
    call save
    in al,0a6h
    and al,1
    mov [saved_page],al
    mov al,1
    out 6ah,al
.case:
    mov byte [page],0
.seedpage:
    mov al,[page]
    out 0a6h,al
    xor al,al
    out 7ch,al
    mov byte [plane],0
.seedplane:
    call plane_segment
    call seed_value
    xor di,di
    mov cx,4000h
    rep stosw
    inc byte [plane]
    cmp byte [plane],4
    jb .seedplane
    inc byte [page]
    cmp byte [page],2
    jb .seedpage
    mov byte [page],0
.writepage:
    mov al,[page]
    out 0a6h,al
    mov byte [plane],0
.writeplane:
    call make_source
    call plane_segment
    cmp byte [operation],2
    jb .plain
    mov al,0c0h
    out 7ch,al
    mov si,tiles
    mov cx,4
.tiles:
    lodsb
    out 7eh,al
    loop .tiles
.plain:
    push ds
    mov ds,[source_seg]
    xor si,si
    xor di,di
    mov cx,4000h
    cmp byte [cs:operation],1
    je .bytes
    cmp byte [cs:operation],3
    je .fill
    rep movsw
    jmp .written
.bytes:
    shl cx,1
    rep movsb
    jmp .written
.fill:
    mov ax,0a55ah
    rep stosw
.written:
    pop ds
    xor al,al
    out 7ch,al
    cmp byte [operation],2
    jae .nextpage
    inc byte [plane]
    cmp byte [plane],4
    jb .writeplane
.nextpage:
    inc byte [page]
    cmp byte [page],2
    jb .writepage
    mov byte [page],0
.readpage:
    mov al,[page]
    out 0a6h,al
    mov byte [plane],0
.readplane:
    mov al,[operation]
    mov [record],al
    mov al,[page]
    mov [record+1],al
    mov al,[plane]
    mov [record+2],al
    mov dx,record
    mov cx,8
    call save
    call plane_segment
    push ds
    push es
    pop ds
    push cs
    pop es
    mov di,BUFFER
    xor bx,bx
.sample:
    mov si,bx
    mov cl,9
    shl si,cl
    mov ax,bx
    imul ax,7
    and ax,127
    add si,ax
    cmp bx,63
    jne .offset
    mov si,7fc0h
.offset:
    mov cx,64
    rep movsb
    inc bx
    cmp bx,64
    jb .sample
    pop ds
    mov dx,BUFFER
    mov cx,4096
    call save
    inc byte [plane]
    cmp byte [plane],4
    jb .readplane
    inc byte [page]
    cmp byte [page],2
    jb .readpage
    inc byte [operation]
    cmp byte [operation],4
    jb .case
    xor al,al
    out 7ch,al
    mov al,[saved_page]
    out 0a6h,al
    mov bx,[handle]
    mov ah,3eh
    int 21h
    jc failed
    mov ah,0dh
    int 21h
    mov dx,success_text
    jmp finish
plane_segment:
    xor bx,bx
    mov bl,[plane]
    shl bx,1
    mov es,[segments+bx]
    ret
seed_value:
    mov al,[page]
    mov ah,37
    mul ah
    mov dx,ax
    mov al,[plane]
    mov ah,61
    mul ah
    add ax,dx
    add al,3
    mov ah,al
    xor ah,0ffh
    ret
make_source:
    mov es,[source_seg]
    call seed_value
    mov dx,ax
    xor di,di
    xor bx,bx
    mov cx,4000h
.word:
    mov ax,bx
    imul ax,73
    add ax,dx
    mov si,bx
    shl si,3
    xor ax,si
    stosw
    inc bx
    loop .word
    ret
save:
    mov bx,[handle]
    mov ah,40h
    int 21h
    jc failed
    cmp ax,cx
    jne failed
    ret
critical_error:
    mov al,3
    iret
failed:
    xor al,al
    out 7ch,al
    mov dx,failure_text
finish:
    mov ah,9
    int 21h
    sti
.halt:
    hlt
    jmp .halt
operation: db 0
page: db 0
plane: db 0
saved_page: db 0
source_seg: dw 0
handle: dw 0
segments: dw 0a800h,0b000h,0b800h,0e000h
tiles: db 3ch,0a5h,5ah,0c3h
header: db 'Z98BLK1',0
    dw 32,4096,32768,0
record: times 8 db 0
filename: db 'Z98BLK.BIN',0
success_text: db 'VRAM bulk capture saved: Z98BLK.BIN',13,10,'$'
failure_text: db 'VRAM bulk capture FAILED',13,10,'$'
%if ($-$$+100h)>BUFFER
    %error Code overlaps buffer
%endif
