; SPDX-License-Identifier: GPL-3.0-or-later
; CRC32 all matching files through DOS; save only to a separate result floppy.
bits 16
cpu 386
org 100h
DTA equ 1800h
RESULT equ 2000h
BUFFER equ 4000h
start:
    cli
    mov ax,cs
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,0fffeh
    sti
    cld
    add ax,1000h
    jc failed
    cmp [2],ax
    jb failed
    mov dx,start_text
    mov ah,9
    int 21h
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dl,1                    ; source files are on B:, result disk is A:
    mov ah,0eh
    int 21h
    mov dx,drive_text
    mov ah,9
    int 21h
    mov si,header
    mov di,RESULT
    mov cx,16
    rep movsb
    mov word [position],RESULT+16
    mov dx,DTA
    mov ah,1ah
    int 21h
    mov dx,pattern
    xor cx,cx
    mov ah,4eh
    int 21h
    jc failed
.file:
    cmp word [RESULT+8],64
    jae failed
    mov di,[position]
    push di
    mov cx,16
    xor ax,ax
    rep stosw
    pop di
    mov si,DTA+30
    mov cx,13
    rep movsb
    mov di,[position]
    mov eax,[DTA+26]
    mov [di+16],eax
    mov dx,DTA+30
    mov ax,3d00h
    int 21h
    jc failed
    mov [handle],ax
    mov dword [crc],0ffffffffh
    mov dword [amount],0
.read:
    mov bx,[handle]
    mov dx,BUFFER
    mov cx,1024
    mov ah,3fh
    int 21h
    jc failed
    test ax,ax
    jz .eof
    mov cx,ax
    movzx eax,ax
    add [amount],eax
    mov si,BUFFER
    mov edx,[crc]
.byte:
    lodsb
    xor dl,al
    mov bp,8
.bit:
    shr edx,1
    jnc .next
    xor edx,0edb88320h
.next:
    dec bp
    jnz .bit
    loop .byte
    mov [crc],edx
    jmp .read
.eof:
    mov bx,[handle]
    mov ah,3eh
    int 21h
    jc failed
    mov di,[position]
    mov eax,[crc]
    not eax
    mov [di+20],eax
    mov eax,[amount]
    mov [di+24],eax
    cmp eax,[di+16]
    jne failed
    add word [position],32
    inc word [RESULT+8]
    mov dx,progress_text
    mov ah,9
    int 21h
    mov ah,4fh
    int 21h
    jnc .file
    cmp ax,18
    jne failed
    mov dx,output_name
    mov ax,5b00h
    xor cx,cx
    int 21h
    jc failed
    mov bx,ax
    mov dx,RESULT
    mov cx,[position]
    sub cx,RESULT
    mov [write_amount],cx
    mov ah,40h
    int 21h
    jc failed
    cmp ax,[write_amount]
    jne failed
    mov ah,3eh
    int 21h
    jc failed
    mov ah,0dh
    int 21h
    mov dx,success_text
    jmp finish
critical_error:
    mov al,3
    iret
failed:
    mov dx,failure_text
finish:
    mov ah,9
    int 21h
    sti
.halt:
    hlt
    jmp .halt
position: dw 0
handle: dw 0
write_amount: dw 0
crc: dd 0
amount: dd 0
header: db 'Z98FCRC1'
    dw 0,32,0,0
pattern: db '*.?ZH',0
output_name: db 'A:\Z98FCRC.BIN',0
start_text: db 'File CRC probe started',13,10,'$'
drive_text: db 'Reading graphics from B:',13,10,'$'
progress_text: db '.$'
success_text: db 'DOS graphics-file CRC32 saved to A:\Z98FCRC.BIN',13,10,'$'
failure_text: db 'DOS graphics-file CRC32 FAILED',13,10,'$'
%if ($-$$+100h)>DTA
    %error Code overlaps DTA
%endif
