; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored DOS full-file read/CRC control. No game code.
; Two sequential passes: read only, then table CRC32 with each chunk checkpoint.
; RTC whole seconds, 120 second budget BETWEEN calls; host deadline required.
bits 16
cpu 386
org 100h
TABLE equ 1000h
RESULT equ 2000h
BUFFER equ 4000h
CHUNK equ 8000h
MAXIMUM equ 2000000h
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
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,banner
    mov ah,9
    int 21h
    mov di,RESULT
    xor ax,ax
    mov cx,2080
    rep stosw
    mov si,magic
    mov di,RESULT
    mov cx,8
    rep movsb
    mov dx,output_name
    xor cx,cx
    mov ax,5b00h
    int 21h
    jc fail
    mov [destination],ax
    call read_rtc
    mov [phase_start],eax
    mov ebp,131072
.clock_live:
    call read_rtc
    cmp eax,[phase_start]
    jne .clock_ok
    dec ebp
    jnz .clock_live
    jmp fail
.clock_ok:
    ; Generate reflected IEEE CRC32 table independently of input.
    xor bx,bx
.table:
    movzx eax,bx
    shr eax,2
    mov cx,8
.bit:
    shr eax,1
    jnc .next_bit
    xor eax,0edb88320h
.next_bit:
    loop .bit
    mov [TABLE+bx],eax
    add bx,4
    cmp bx,1024
    jb .table
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
    cmp eax,12
    jb fail
    cmp eax,MAXIMUM
    ja fail
    mov [RESULT+8],eax
    mov byte [phase],0
.pass:
    mov bx,[source]
    xor cx,cx
    xor dx,dx
    mov ax,4200h
    int 21h
    jc fail
    mov dword [total],0
    mov word [chunks],0
    mov edi,0ffffffffh
    call read_rtc
    mov [phase_start],eax
.read:
    mov eax,[RESULT+8]
    sub eax,[total]
    jz .eof
    cmp eax,CHUNK
    jbe .sized
    mov eax,CHUNK
.sized:
    mov [requested],ax
    mov cx,ax
    mov bx,[source]
    mov dx,BUFFER
    mov ah,3fh
    int 21h
    jc fail
    cmp ax,[requested]
    jne fail
    movzx eax,ax
    add [total],eax
    cmp byte [phase],0
    je .progress
    mov cx,[requested]
    mov si,BUFFER
.crc:
    lodsb
    mov ebx,edi
    xor bl,al
    and ebx,255
    shl bx,2
    shr edi,8
    xor edi,[TABLE+bx]
    loop .crc
    mov bx,[chunks]
    shl bx,2
    mov eax,edi
    not eax
    mov [RESULT+64+bx],eax
.progress:
    inc word [chunks]
    call budget
    test word [chunks],31
    jnz .read
    mov dx,dot
    mov ah,9
    int 21h
    jmp .read
.eof:
    ; Detect growth since size query as well as short reads/truncation.
    mov bx,[source]
    mov dx,BUFFER
    mov cx,1
    mov ah,3fh
    int 21h
    jc fail
    test ax,ax
    jnz fail
    call budget
    cmp byte [phase],0
    jne .finish_crc
    mov [RESULT+12],eax
    mov byte [phase],1
    mov dx,crc_banner
    mov ah,9
    int 21h
    jmp .pass
.finish_crc:
    mov [RESULT+16],eax
    not edi
    mov [RESULT+20],edi
    movzx eax,word [chunks]
    mov [RESULT+24],eax
    mov dword [RESULT+28],CHUNK
    mov bx,[source]
    mov ah,3eh
    int 21h
    jc fail
    mov bx,[destination]
    mov dx,RESULT
    mov cx,[chunks]
    shl cx,2
    add cx,64
    mov [requested],cx
    mov ah,40h
    int 21h
    jc fail
    cmp ax,[requested]
    jne fail
    mov bx,[destination]
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
budget:
    call read_rtc
    sub eax,[phase_start]
    jnc .done
    add eax,86400
.done:
    cmp eax,120
    jae fail
    ret
; BIOS INT1C AH00 latches PC98 RTC to ES:BX. Other GPRs preserved.
read_rtc:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    push ds
    push es
    push cs
    pop es
    mov bx,rtc_buffer
    xor ah,ah
    int 1ch
    pop es
    pop ds
    mov al,[rtc_buffer+3]
    call bcd
    cmp eax,23
    ja fail
    imul eax,eax,3600
    mov ebx,eax
    mov al,[rtc_buffer+4]
    call bcd
    cmp eax,59
    ja fail
    imul eax,eax,60
    add ebx,eax
    mov al,[rtc_buffer+5]
    call bcd
    cmp eax,59
    ja fail
    add eax,ebx
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret
bcd:
    movzx eax,al
    mov edx,eax
    and eax,15
    cmp eax,9
    ja fail
    shr edx,4
    cmp edx,9
    ja fail
    imul edx,edx,10
    add eax,edx
    ret
critical_error:
    mov al,3
    iret
fail:
    mov dx,failure
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
source: dw 0
destination: dw 0
requested: dw 0
chunks: dw 0
phase: db 0
total: dd 0
phase_start: dd 0
rtc_buffer: times 6 db 0
magic: db 'Z98READ1'
input_name: db 'A:\DOOM1\DOOM.WAD',0
output_name: db 'A:\WADREAD.BIN',0
banner: db 'Full WAD read R1: sequential read-only pass (120s limit).',13,10,'$'
crc_banner: db 13,10,'Full WAD read R1: CRC32 pass (120s limit).',13,10,'$'
dot: db '.$'
success: db 13,10,'Reads completed: WADREAD.BIN. Host CRC comparison REQUIRED.',13,10,'$'
failure: db 13,10,'WAD read probe FAILED. No success claimed.',13,10,'$'
%if ($-$$+100h)>TABLE
    %error Code overlaps CRC table
%endif
