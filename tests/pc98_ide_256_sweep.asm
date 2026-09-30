; SPDX-License-Identifier: GPL-3.0-or-later
; Actual CPU/BIOS test of 256-byte caller sectors (native SASI-era HDI images)
; over 512-byte ATA blocks: every read case starts on an even or odd sector,
; so half the transfers begin in the middle of a block. Disk bytes follow the
; testbench pattern: word (A55Ah ^ LBA ^ index) at each 512-byte block.
; With BIOS_ALLOW_WRITES, half-block writes must preserve the other half.
bits 16
cpu 386
org 1000h
%define BIOS_HEADS 8
%define BIOS_SECTORS 33
%define BIOS_CYLINDERS 615
%define BIOS_BPS 256
%define BIOS_POLL_LIMIT 256
%ifdef BIOS_WRITE_SWEEP
%define BIOS_ALLOW_WRITES 1
%define BIOS_WRITE_FIRST_LBA 17
%define BIOS_WRITE_LAST_LBA 18
%endif
start:
    cli
    xor ax,ax
    mov ss,ax
    mov sp,7000h
    mov ds,ax
    mov es,ax
    cld
    mov word [1bh*4],bios_int1b
    mov word [1bh*4+2],0
    mov word [sec_index],0
.sector:
    mov word [len_index],0
.length:
    mov bx,[sec_index]
    mov ax,[sectors+bx]
    mov [start_sector],ax
    mov bx,[len_index]
    mov ax,[lengths+bx]
    mov [length],ax
    ; linear read: AL=00h, DL:CX = sector, BX = bytes, ES:BP = buffer
    call fill_guard
    mov bx,[length]
    mov cx,[start_sector]
    xor dx,dx
    mov bp,100h
    mov ax,0600h
    int 1bh
    jc failed
    call check_guard
    movzx eax,word [start_sector]
    shl eax,8
    mov di,100h
    mov cx,[length]
    call verify_disk
    add word [len_index],2
    cmp word [len_index],lengths_end-lengths
    jb .length
    add word [sec_index],2
    cmp word [sec_index],sectors_end-sectors
    jb .sector
    ; CHS read: cylinder 0, head 1, sector 2 = native sector 35
    mov word [length],300
    call fill_guard
    mov bx,300
    xor cx,cx
    mov dx,0102h
    mov bp,100h
    mov ax,0680h
    int 1bh
    jc failed
    call check_guard
    mov eax,35*256
    mov di,100h
    mov cx,300
    call verify_disk
    ; Sense reports 256-byte sectors.
    mov ax,8480h
    int 1bh
    cmp bx,256
    jne failed
%ifdef BIOS_WRITE_SWEEP
    ; a) second half of block 17 (native 35)
    mov al,3
    mov ah,7
    mov cx,256
    call fill_pattern
    mov bx,256
    mov cx,35
    xor dx,dx
    mov bp,100h
    mov ax,0500h
    int 1bh
    jc failed
    ; b) block 17 read back: original first half, written second half
    mov bx,512
    mov cx,34
    xor dx,dx
    mov bp,100h
    mov ax,0600h
    int 1bh
    jc failed
    mov eax,34*256
    mov di,100h
    mov cx,256
    call verify_disk
    mov al,3
    mov ah,7
    mov di,200h
    mov cx,256
    call verify_pattern
    ; c) 512 bytes from native 35: across blocks 17 (second half) and 18 (first half)
    mov al,1
    mov ah,5
    mov cx,512
    call fill_pattern
    mov bx,512
    mov cx,35
    xor dx,dx
    mov bp,100h
    mov ax,0500h
    int 1bh
    jc failed
    ; d) 1024 bytes from native 34: original, written 512, original
    mov bx,1024
    mov cx,34
    xor dx,dx
    mov bp,100h
    mov ax,0600h
    int 1bh
    jc failed
    mov eax,34*256
    mov di,100h
    mov cx,256
    call verify_disk
    mov al,1
    mov ah,5
    mov di,200h
    mov cx,512
    call verify_pattern
    mov eax,37*256
    mov di,400h
    mov cx,256
    call verify_disk
%endif
    mov dx,7ff0h
    mov ax,600dh
    out dx,ax
    hlt
failed:
    mov dx,7ff0h
    mov ax,0deadh
    out dx,ax
    hlt

; Guard bytes CCh at 2000:00FF .. 2000:0100+length
fill_guard:
    mov ax,2000h
    mov es,ax
    mov di,0ffh
    mov cx,[length]
    add cx,2
    mov al,0cch
    rep stosb
    ret
check_guard:
    cmp byte [es:0ffh],0cch
    jne failed
    mov di,100h
    add di,[length]
    cmp byte [es:di],0cch
    jne failed
    ret

; Verify ES:DI, CX bytes, against the disk pattern from image byte EAX.
verify_disk:
    push eax
.byte:
    mov ebx,eax
    shr ebx,9                   ; block
    mov edx,eax
    shr edx,1
    and dx,255                  ; word index in the block
    xor dx,bx
    xor dx,0a55ah
    test al,1
    jz .low
    shr dx,8
.low:
    cmp dl,[es:di]
    jne failed
    inc di
    inc eax
    loop .byte
    pop eax
    ret

; Pattern byte k = AL + k*AH. Fill 2000:0100, or verify ES:DI.
fill_pattern:
    push ax
    mov bx,2000h
    mov es,bx
    mov di,100h
.fill:
    stosb
    add al,ah
    loop .fill
    pop ax
    ret
verify_pattern:
.check:
    cmp al,[es:di]
    jne failed
    inc di
    add al,ah
    loop .check
    ret

start_sector: dw 0
length: dw 0
sec_index: dw 0
len_index: dw 0
sectors: dw 0,1,2,3,35,100,101
sectors_end:
lengths: dw 1,2,255,256,257,300,511,512,513,767,768,1000,1024,1025
lengths_end:
previous_handler: iret
bios_previous_vector: dw previous_handler,0
%include "software/pc98_ide_read_bios.inc"
