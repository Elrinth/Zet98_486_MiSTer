; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored BIOS READ / VERIFY cost control. No writes to tested disk.
bits 16
cpu 386
org 100h
TABLE equ 1000h
RESULT equ 2000h
BUFFER equ 4000h
CHUNK equ 8000h
%ifndef TOTAL_BYTES
%define TOTAL_BYTES 800000h
%endif
START_LBA equ 136
%if TOTAL_BYTES < CHUNK || (TOTAL_BYTES % CHUNK) != 0 || TOTAL_BYTES > 800000h
%error Invalid bounded transfer length
%endif
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
    mov cx,64
    rep stosw
    mov si,magic
    mov di,RESULT
    mov cx,8
    rep movsb
    mov dword [RESULT+8],START_LBA
    mov dword [RESULT+12],TOTAL_BYTES
    mov dword [RESULT+16],CHUNK
    mov dword [RESULT+20],4
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
    mov word [phase],0
.pass:
    push cs
    pop es
    mov di,BUFFER
    mov ax,0a55ah
    mov cx,CHUNK/2
    rep stosw
    mov word [remaining],TOTAL_BYTES/CHUNK
    mov dword [lba],START_LBA
    mov bx,[phase]
    mov al,[commands+bx]
    mov [command],al
    movzx eax,al
    shl bx,4
    mov [RESULT+32+bx],eax
    mov dx,phase_banner
    mov ah,9
    int 21h
    call read_rtc
    mov [phase_start],eax
.read:
    push cs
    pop es
    mov bp,BUFFER
    mov bx,CHUNK
    mov ecx,[lba]
    mov edx,ecx
    shr edx,16
    xor ax,ax
    mov ah,[command]
    int 1bh
    jc fail
    test ah,ah
    jnz fail
    add dword [lba],CHUNK/512
    call budget
    dec word [remaining]
    jnz .read
    ; budget returned elapsed seconds; checksum is deliberately OUTSIDE timing.
    mov bx,[phase]
    shl bx,4
    mov [RESULT+36+bx],eax
    cmp byte [command],1
    jne .crc_start
    push cs
    pop es
    mov di,BUFFER
    mov ax,0a55ah
    mov cx,CHUNK/2
    repe scasw
    jne fail
.crc_start:
    mov edi,0ffffffffh
    mov si,BUFFER
    mov cx,CHUNK
.crc:
    lodsb
    mov ebx,edi
    xor bl,al
    and ebx,255
    shl bx,2
    shr edi,8
    xor edi,[TABLE+bx]
    loop .crc
    not edi
    mov bx,[phase]
    shl bx,4
    mov [RESULT+40+bx],edi
    mov dword [RESULT+44+bx],1
    inc word [phase]
    cmp word [phase],4
    jb .pass
    mov bx,[destination]
    mov dx,RESULT
    mov cx,128
    mov ah,40h
    int 21h
    jc fail
    cmp ax,128
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
    cmp eax,60
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
phase: dw 0
remaining: dw 0
command: db 0
commands: db 6,1,1,6
phase_start: dd 0
lba: dd 0
destination: dw 0
rtc_buffer: times 6 db 0
magic: db 'Z98BIO1',0
output_name: db 'A:\BIOSCOST.BIN',0
banner: db 'BIOS read/verify cost R1: 4 x 8MiB, no disk writes.',13,10,'$'
phase_banner: db 'Starting next bounded BIOS pass.',13,10,'$'
success: db 'Four passes complete: BIOSCOST.BIN. Host comparison required.',13,10,'$'
failure: db 'BIOS cost probe FAILED. No success claimed.',13,10,'$'
%if ($-$$+100h)>TABLE
%error Code overlaps table
%endif
