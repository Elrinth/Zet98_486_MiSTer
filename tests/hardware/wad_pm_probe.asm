; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored DOS->XMS->protected32 full payload control. Read-only WAD.
; New disposable fixture only; not a modified Doom executable. No performance
; claim. At most 32MB/1024 chunks; host watchdog required for stuck DOS/XMS.
bits 16
cpu 386
org 100h
%define RESULT 2000h
%define BUFFER 4000h
%define CHUNK 32768
start:
    push cs
    pop ds
    push cs
    pop es
    cld
    mov ax,cs
    add ax,1000h
    jc early_fail
    cmp ax,[2]
    ja early_fail
    smsw ax
    test al,1
    jnz early_fail                 ; Refuse EMM386/other protected environments
    mov ax,3524h
    int 21h
    mov [old24],bx
    mov [old24+2],es
    mov dx,critical
    mov ax,2524h
    int 21h
    push cs
    pop es
    mov di,RESULT
    xor ax,ax
    mov cx,2080                   ; 64 header + 1024 CRC checkpoints
    rep stosw
    mov si,magic
    mov di,RESULT
    mov cx,8
    rep movsb
    mov word [RESULT+8],1         ; Pending/failure until all cleanup succeeds
    mov dx,output_name
    xor cx,cx
    mov ah,5bh
    int 21h
    jc restore24
    mov [output],ax
    mov ax,4300h
    int 2fh
    cmp al,80h
    jne fail
    mov ax,4310h
    int 2fh
    mov [xms],bx
    mov [xms+2],es
    mov dx,input_name
    mov ax,3d00h
    int 21h
    jc fail
    mov [input],ax
    mov bx,ax
    xor cx,cx
    xor dx,dx
    mov ax,4202h
    int 21h
    jc fail
    movzx eax,ax
    movzx edx,dx
    shl edx,16
    or eax,edx
    cmp eax,12
    jb fail
    cmp eax,2000000h
    ja fail
    mov [RESULT+12],eax
    add eax,1023
    shr eax,10
    mov dx,ax
    mov ah,9
    call far [xms]
    cmp ax,1
    jne fail
    mov [handle],dx
    mov bx,[input]
    xor cx,cx
    xor dx,dx
    mov ax,4200h
    int 21h
    jc fail
.load:
    mov eax,[RESULT+12]
    sub eax,[RESULT+16]
    jz .eof
    cmp eax,CHUNK
    jbe .size
    mov eax,CHUNK
.size:
    mov [wanted],ax
    mov cx,ax
    mov dx,BUFFER
    mov bx,[input]
    mov ah,3fh
    int 21h
    jc fail
    cmp ax,[wanted]
    jne fail
    ; XMS moves require an even length; zero-pad only the allocation's tail.
    movzx eax,ax
    mov bx,ax
    mov byte [BUFFER+bx],0
    inc eax
    and eax,0fffffffeh
    mov [move],eax
    mov word [move+4],0
    mov word [move+6],BUFFER
    mov ax,cs
    mov [move+8],ax
    mov ax,[handle]
    mov [move+10],ax
    mov eax,[RESULT+16]
    mov [move+12],eax
    mov si,move
    mov ah,0bh
    call far [xms]
    cmp ax,1
    jne fail
    movzx eax,word [wanted]
    add [RESULT+16],eax
    jmp .load
.eof:
    mov bx,[input]
    mov dx,BUFFER
    mov cx,1
    mov ah,3fh
    int 21h
    jc fail
    test ax,ax
    jnz fail
    mov ah,0ch
    mov dx,[handle]
    call far [xms]
    cmp ax,1
    jne fail
    mov byte [locked],1
    movzx eax,dx
    shl eax,16
    mov ax,bx
    mov [RESULT+20],eax
    cmp eax,100000h
    jb fail
    add eax,[RESULT+12]
    jc fail
    mov ah,5                      ; Local A20 reference held until all PM reads
    call far [xms]
    cmp ax,1
    jne fail
    mov byte [a20],1
    push cs
    pop es
    cld
    mov di,pm_table
    xor ebx,ebx
.table:
    mov eax,ebx
    mov cx,8
.bit:
    shr eax,1
    jnc .next_bit
    xor eax,0edb88320h
.next_bit:
    loop .bit
    stosd
    inc ebx
    cmp ebx,256
    jb .table
    call pm_initialize
    mov dword [pm_crc],0ffffffffh
.verify:
    mov eax,[RESULT+12]
    sub eax,[RESULT+24]
    jz .verified
    cmp eax,CHUNK
    jbe .window
    mov eax,CHUNK
.window:
    mov [pm_length],eax
    mov eax,[RESULT+20]
    add eax,[RESULT+24]
    mov [pm_address],eax
    call pm_window
    cmp byte [pm_fault],0
    jne fail
    mov eax,[pm_length]
    add [RESULT+24],eax
    mov bx,[RESULT+28]
    shl bx,2
    mov eax,[pm_crc]
    not eax
    mov [RESULT+64+bx],eax
    inc word [RESULT+28]
    jmp .verify
.verified:
    mov word [RESULT+8],0
fail:
    ; Every resource acquired is released even after a checked failure.
    cmp byte [a20],0
    je .unlock
    mov ah,6
    call far [xms]
    cmp ax,1
    je .unlock
    mov word [RESULT+8],2
.unlock:
    cmp byte [locked],0
    je .free
    mov dx,[handle]
    mov ah,0dh
    call far [xms]
    cmp ax,1
    je .free
    mov word [RESULT+8],3
.free:
    mov dx,[handle]
    test dx,dx
    jz .close
    mov ah,0ah
    call far [xms]
    cmp ax,1
    je .close
    mov word [RESULT+8],4
.close:
    mov bx,[input]
    cmp bx,0ffffh
    je .write
    mov ah,3eh
    int 21h
    jnc .write
    mov word [RESULT+8],5
.write:
    mov cx,[RESULT+28]
    shl cx,2
    add cx,64
    mov [wanted],cx
    mov bx,[output]
    mov dx,RESULT
    mov ah,40h
    int 21h
    jc .write_failed
    cmp ax,[wanted]
    je .close_output
.write_failed:
    mov word [RESULT+8],6
.close_output:
    mov bx,[output]
    mov ah,3eh
    int 21h
    jnc restore24
    mov word [RESULT+8],7
restore24:
    push ds
    lds dx,[old24]
    mov ax,2524h
    int 21h
    pop ds
    mov dx,message
    mov ah,9
    int 21h
    mov ax,4c01h
    cmp word [RESULT+8],0
    jne .exit
    xor al,al
.exit:
    int 21h
early_fail:
    mov ax,4c02h
    int 21h
critical:
    mov al,3
    iret
input: dw 0ffffh
output: dw 0ffffh
handle: dw 0
locked: db 0
a20: db 0
wanted: dw 0
old24: dd 0
xms: dd 0
move: times 16 db 0
magic: db 'Z98PMRD1'
input_name: db 'A:\DOOM1\DOOM.WAD',0
output_name: db 'A:\WADPM.BIN',0
message: db 'WAD protected-memory probe ended. Host WADPM.BIN validation required.',13,10,'$'
%include "tests/hardware/pm_crc_window.inc"
%if ($-$$+100h)>1000h
    %error Code overlaps CRC table
%endif
