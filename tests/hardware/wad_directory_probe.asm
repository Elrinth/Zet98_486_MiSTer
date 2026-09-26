; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored, read-only DOS WAD header/directory reader. No game code.
; Saves a new WADDIR.BIN only; never overwrites an existing result.
bits 16
cpu 386
org 100h
RESULT equ 2000h
DIRECTORY equ RESULT+64
start:
    cld
    push cs
    pop ds
    push cs
    pop es
    mov ax,cs
    add ax,1000h
    jc fail
    cmp [2],ax
    jb fail
    mov dx,banner
    mov ah,9
    int 21h
    mov di,RESULT
    xor ax,ax
    mov cx,32
    rep stosw
    mov si,magic
    mov di,RESULT
    mov cx,8
    rep movsb
    mov dx,input_name
    mov ax,3d00h
    int 21h
    jc fail
    mov [source],ax
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
    mov [RESULT+8],eax
    xor cx,cx
    xor dx,dx
    mov ax,4200h
    int 21h
    jc fail
    mov dx,RESULT+12
    mov cx,12
    mov ah,3fh
    int 21h
    jc fail
    cmp ax,12
    jne fail
    cmp dword [RESULT+12],'IWAD'
    je .signature_ok
    cmp dword [RESULT+12],'PWAD'
    jne fail
.signature_ok:
    mov eax,[RESULT+16]
    test eax,eax
    jz fail
    cmp eax,2048
    ja fail
    shl eax,4
    mov [remaining],ax
    add eax,[RESULT+20]
    jc fail
    cmp eax,[RESULT+8]
    ja fail
    mov edx,[RESULT+20]
    mov ecx,edx
    shr ecx,16
    mov ax,4200h
    int 21h
    jc fail
    mov word [position],DIRECTORY
.read:
    mov cx,[remaining]
    cmp cx,1024
    jbe .size_ok
    mov cx,1024
.size_ok:
    mov [requested],cx
    mov bx,[source]
    mov dx,[position]
    mov ah,3fh
    int 21h
    jc fail
    cmp ax,[requested]
    jne fail
    add [position],ax
    sub [remaining],ax
    mov dx,dot
    mov ah,9
    int 21h
    cmp word [remaining],0
    jne .read
    mov bx,[source]
    mov ah,3eh
    int 21h
    jc fail
    mov si,DIRECTORY
    mov cx,[RESULT+16]
.validate:
    mov eax,[si]
    add eax,[si+4]
    jc fail
    cmp eax,[RESULT+8]
    ja fail
    add si,16
    loop .validate
    mov eax,[RESULT+16]
    mov [RESULT+28],eax
    mov si,DIRECTORY
    mov cx,[position]
    sub cx,DIRECTORY
    mov edx,0ffffffffh
.byte:
    lodsb
    xor dl,al
    mov bp,8
.bit:
    shr edx,1
    jnc .no_xor
    xor edx,0edb88320h
.no_xor:
    dec bp
    jnz .bit
    loop .byte
    not edx
    mov [RESULT+24],edx
    mov si,names
    mov word [position_index],RESULT+32
    mov word [names_left],5
.name:
    mov eax,[si]
    mov edx,[si+4]
    mov edi,0ffffffffh
    mov bx,DIRECTORY
    mov cx,[RESULT+16]
    xor bp,bp
.search:
    cmp eax,[bx+8]
    jne .next_entry
    cmp edx,[bx+12]
    jne .next_entry
    movzx edi,bp
.next_entry:
    add bx,16
    inc bp
    loop .search
    mov bx,[position_index]
    mov [bx],edi
    add word [position_index],4
    add si,8
    dec word [names_left]
    jnz .name
    mov dx,output_name
    xor cx,cx
    mov ax,5b00h
    int 21h
    jc fail
    mov bx,ax
    mov dx,RESULT
    mov cx,[position]
    sub cx,RESULT
    mov [requested],cx
    mov ah,40h
    int 21h
    jc fail
    cmp ax,[requested]
    jne fail
    mov ah,3eh
    int 21h
    jc fail
    mov ah,0dh
    int 21h
    mov dx,success
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
fail:
    mov dx,failure
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
source: dw 0
remaining: dw 0
requested: dw 0
position: dw 0
position_index: dw 0
names_left: dw 0
magic: db 'Z98WAD1',0
names: db 'DEMO1',0,0,0,'DEMO3',0,0,0,'TITLEPIC','E1M1',0,0,0,0,'E1M2',0,0,0,0
input_name: db 'A:\DOOM1\DOOM.WAD',0
output_name: db 'A:\WADDIR.BIN',0
banner: db 'Reading WAD directory through DOS (up to 32 chunks).',13,10,'$'
dot: db '.$'
success: db 13,10,'Directory/bounds/CRC complete: A:\WADDIR.BIN',13,10,'$'
failure: db 13,10,'WAD directory probe FAILED; no success claimed.',13,10,'$'
%if ($-$$+100h)>RESULT
    %error Code overlaps results
%endif
