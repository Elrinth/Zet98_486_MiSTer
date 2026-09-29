; SPDX-License-Identifier: GPL-3.0-or-later
; RAM-resident half of the Zet98 PC-98 disk option ROM. Only our D8000-DFFFF
; reserved RAM is used for code, state, scratch sectors and private stacks.
bits 16
cpu 386
org 0
%define RESIDENT_SEGMENT 0d800h
%define IPL_BUFFER 4000h
%define SECTOR_BUFFER 4400h
%define BIOS_DYNAMIC_GEOMETRY 1
%define BIOS_ALLOW_WRITES 1
    jmp near initialize
    jmp near boot
    db 'ZB'
    dw int1f_handler              ; offset 8: INT 1Fh block move (tests hook it directly)
state: db 0                       ; 1 ready, 2 absent, 3 read error, 4 geometry
init_ss: dw 0
init_sp: dw 0
bios_heads: dd 0
bios_sectors: dd 0
bios_cylinders: dd 0
bios_capacity: dd 0
bios_previous_vector: dd 0
caller_ss: dw 0
caller_sp: dw 0
caller_ax: dw 0
result_flags: dw 0
resident_handler: dw bios_int1b,RESIDENT_SEGMENT
partition: dw 0
candidate: dw 0
int1f_previous: dd 0

initialize:
    cli
    mov ax,ss
    mov [cs:init_ss],ax
    mov [cs:init_sp],sp
    mov ax,cs
    mov ss,ax
    mov sp,7ffeh
    mov ds,ax
    mov es,ax
    cld
    ; INT 1Fh AH=90h (extended memory block move, used by HIMEM.SYS for all
    ; XMS copies). The PC-9801VM BIOS cannot reach memory above 1 MB.
    push es
    xor ax,ax
    mov es,ax
    mov eax,[es:1fh*4]
    mov [int1f_previous],eax
    mov word [es:1fh*4],int1f_handler
    mov word [es:1fh*4+2],cs
    pop es
    mov byte [state],2
    call bios_present
    jc .return
    mov byte [state],3
    mov dx,074ch
    mov al,2
    out dx,al
    mov dx,064ch
    mov al,0e0h
    out dx,al
    mov dx,064eh
    mov al,0ech
    out dx,al
    call bios_wait_data
    jc .return
    mov dx,0640h
    mov di,SECTOR_BUFFER
    mov cx,256
    rep insw
    call bios_end_pio
    mov eax,[SECTOR_BUFFER+120]
    test eax,eax
    jz .return
    cmp eax,10000000h
    ja .return
    mov [bios_capacity],eax
    xor esi,esi
    mov di,IPL_BUFFER
    call read_one
    jc .return
    inc esi
    mov di,IPL_BUFFER+512
    call read_one
    jc .return
    mov byte [state],4
    cmp word [IPL_BUFFER+510],0aa55h
    jne .return
    ; Try the partition IPL CHS under common PC-98 geometries. A candidate
    ; must agree with its own DOS BPB, hidden-sector LBA and image capacity.
    ; Reads alone are performed until a candidate is validated.
    mov word [partition],IPL_BUFFER+512
.partition:
    mov bx,[partition]
    mov al,[bx]
    and al,7fh
    cmp al,21h                    ; PC-98 DOS FAT partition
    jne .next_partition
    mov word [candidate],geometries
.candidate:
    mov bx,[candidate]
    movzx eax,byte [bx]
    test eax,eax
    jz .next_partition
    mov [bios_heads],eax
    movzx eax,byte [bx+1]
    mov [bios_sectors],eax
    mov bx,[partition]
    movzx esi,word [bx+6]
    imul esi,[bios_heads]
    movzx eax,byte [bx+5]
    cmp eax,[bios_heads]
    jae .next_candidate
    add esi,eax
    imul esi,[bios_sectors]
    movzx eax,byte [bx+4]
    cmp eax,[bios_sectors]
    jae .next_candidate
    add esi,eax
    test esi,esi
    jz .next_candidate
    mov di,SECTOR_BUFFER
    call read_one
    jc .next_candidate
    ; DOS logical sectors need not equal the ATA sector size. PC-98 HDDs
    ; commonly use 1024-byte FAT sectors over 512-byte physical sectors.
    mov ax,[SECTOR_BUFFER+11]
    cmp ax,512
    je .bpb_geometry
    cmp ax,1024
    je .bpb_geometry
    cmp ax,2048
    jne .next_candidate
.bpb_geometry:
    mov ax,[bios_sectors]
    cmp [SECTOR_BUFFER+24],ax
    jne .legacy_bpb
    mov ax,[bios_heads]
    cmp [SECTOR_BUFFER+26],ax
    jne .legacy_bpb
    cmp [SECTOR_BUFFER+28],esi
    je .bpb_valid
.legacy_bpb:
    ; Older NEC DOS IPLs store the physical hidden-sector DWORD at 18h
    ; and physical sector bytes at 1Eh, instead of the extended DOS BPB's
    ; track/head fields. Require both to agree with this candidate.
    cmp [SECTOR_BUFFER+24],esi
    jne .next_candidate
    cmp word [SECTOR_BUFFER+30],512
    jne .next_candidate
    cmp word [SECTOR_BUFFER+19],0
    je .next_candidate           ; no extended total-sectors field here
.bpb_valid:
    mov al,[SECTOR_BUFFER+13]
    test al,al
    jz .next_candidate
    mov ah,al
    dec ah
    test al,ah                   ; sectors per cluster must be a power of two
    jnz .next_candidate
    cmp word [SECTOR_BUFFER+14],0
    je .next_candidate
    mov al,[SECTOR_BUFFER+16]
    dec al
    cmp al,1                     ; one or two FATs
    ja .next_candidate
    cmp word [SECTOR_BUFFER+17],0
    je .next_candidate           ; FAT32 is not supported by this boot BIOS
    cmp word [SECTOR_BUFFER+22],0
    je .next_candidate
    movzx eax,word [SECTOR_BUFFER+19]
    test eax,eax
    jnz .size
    mov eax,[SECTOR_BUFFER+32]
.size:
    test eax,eax
    jz .next_candidate
    movzx ecx,word [SECTOR_BUFFER+11]
    shr ecx,9                   ; logical DOS sectors -> physical ATA LBAs
    mul ecx
    test edx,edx
    jnz .next_candidate
    add eax,esi
    jc .next_candidate
    cmp eax,[bios_capacity]
    ja .next_candidate
    mov eax,[bios_heads]
    imul eax,[bios_sectors]
    mov ecx,eax
    mov eax,[bios_capacity]
    xor edx,edx
    div ecx
    test eax,eax
    jz .next_candidate
    cmp eax,65535
    ja .next_candidate
    mov [bios_cylinders],eax
    xor ax,ax
    mov es,ax
    mov eax,[es:1bh*4]
    mov [bios_previous_vector],eax
    ; Only retain a ROM handler across OS load, never a stale RAM hook.
    movzx eax,word [bios_previous_vector+2]
    shl eax,4
    movzx edx,word [bios_previous_vector]
    add eax,edx
    cmp eax,0e8000h
    jb .return
    cmp eax,100000h
    jae .return
    mov word [es:1bh*4],bios_stack_int1b
    mov word [es:1bh*4+2],cs
    or word [es:055ch],0100h
    mov byte [state],1
    jmp .return
.next_candidate:
    add word [candidate],2
    jmp .candidate
.next_partition:
    add word [partition],32
    cmp word [partition],IPL_BUFFER+1024
    jb .partition
.return:
    call bios_end_pio
    mov ax,[cs:init_ss]
    mov ss,ax
    mov sp,[cs:init_sp]
    retf

; Read a single LBA at ESI into CS:DI without disturbing the scan registers.
read_one:
    pushad
    push es
    push cs
    pop es
    cmp esi,[cs:bios_capacity]
    jae .error
    mov dx,074ch
    mov al,2
    out dx,al
    call bios_wait_idle
    jc .error
    call bios_program_sector
    mov al,20h
    out dx,al
    call bios_wait_data
    jc .error
    mov dx,0640h
    mov cx,256
    rep insw
    mov dx,064eh
    in al,dx
    test al,21h
    jnz .error
    clc
    jmp .done
.error:
    stc
.done:
    pop es
    popad
    ret

boot:
    cmp al,0ah                   ; explicit first hard drive position
    je .selected
    cmp al,1                     ; first pass of the automatic boot order
    jne .return
    ; Claim automatic boot before the BIOS retries empty floppy drives.
    ; A manually selected boot priority still follows the BIOS's order.
    ; A3FF2 is protected NVRAM (and aliases A3FF0), not a writable mirror.
    push ax
    push es
    mov ax,0a000h
    mov es,ax
    test byte [es:3ff2h],0f0h
    pop es
    pop ax
    jnz .return
    cmp byte [cs:state],1
    jne .return
.selected:
    cmp byte [cs:state],2         ; no image: leave floppy/BASIC fallbacks alone
    je .return
    cli
    mov ax,cs
    mov ss,ax
    mov sp,7ffeh
    mov ds,ax
    cmp byte [state],1
    jne boot_error
    mov ax,1fc0h
    mov es,ax
    xor bp,bp
    xor cx,cx
    xor dx,dx
    mov bx,1024
    mov ax,0680h
    int 1bh
    jc boot_error
    cmp word [es:510],0aa55h
    jne boot_error
    xor ax,ax
    mov ds,ax
    mov byte [0584h],80h
    cld
    sti
    call 1fc0h:0
    jmp boot_error
.return:
    retf

boot_error:
    mov al,7
    out 37h,al                    ; silence a BIOS error tone before stopping
    mov ax,0a04h
    int 18h
    mov ah,0ch
    int 18h
    mov ah,16h
    mov dx,0e120h
    int 18h
    cli
    cld
    push cs
    pop ds
    mov ax,0a000h
    mov es,ax
    mov di,160*10+16
    mov si,error_text
.print:
    lodsb
    test al,al
    jz .stop
    xor ah,ah
    stosw
    mov word [es:di+2000h-2],0e1h
    jmp .print
.stop:
    mov ah,0b0h
    mov al,[state]
    mov dx,7ff0h
    out dx,ax
.halt:
    hlt
    jmp .halt

; Selected calls use a private stack; the partition IPL's SS=0/SP=028E
; otherwise lets the service's sector buffer overwrite interrupt vectors.
; Interrupts run during the service when the caller had them enabled, as with
; NEC's BIOS: a whole disk read with IF=0 held off the timer and sound IRQs
; while each sector came from the MiSTer (Touhou 5 music stuttered on loads).
; A call arriving on the private stack (from an interrupt handler during a
; service) runs there directly and leaves the saved caller state alone.
bios_stack_int1b:
    cmp al,80h
    je .selected
    test al,al
    jz .selected
    jmp far [cs:bios_previous_vector]
.selected:
    push ax
    push bx
    mov ax,ss
    mov bx,cs
    cmp ax,bx
    pop bx
    pop ax
    jne .switch
    jmp far [cs:resident_handler]    ; nested: its IRET returns to the caller
.switch:
    mov [cs:caller_ax],ax
    mov ax,ss
    mov [cs:caller_ss],ax
    mov [cs:caller_sp],sp
    mov ax,cs
    mov ss,ax
    mov sp,6ffeh
    push ds
    push bp
    mov ds,[cs:caller_ss]
    mov bp,[cs:caller_sp]
    test byte [ds:bp+5],2            ; caller's IF (FLAGS bit 9)
    pop bp
    pop ds
    jz .service
    sti
.service:
    mov ax,[cs:caller_ax]
    pushf
    call far [cs:resident_handler]
    cli
    pushf
    pop word [cs:result_flags]
    mov [cs:caller_ax],ax
    push ds
    push bp
    mov ds,[cs:caller_ss]
    mov bp,[cs:caller_sp]
    and word [ds:bp+4],0fffeh
    test byte [cs:result_flags],1
    jz .flags
    or word [ds:bp+4],1
.flags:
    pop bp
    pop ds
    mov ss,[cs:caller_ss]
    mov sp,[cs:caller_sp]
    mov ax,[cs:caller_ax]
    iret

; ---- INT 1Fh AH=90h: block move (NP2kai bios1f.c interface) -------------------
; ES:BX -> descriptor table: source descriptor at +10h, destination at +18h
; (16-bit limit, 24-bit base). SI/DI: offsets, CX: bytes (0 = 64 KiB).
; Returns CF=0 on success. Done in a short 386 protected-mode trip with
; interrupts off; A20 is enabled for the copy and restored afterwards. From
; protected or V86 mode (e.g. EMM386 active) the previous handler is used.
int1f_handler:
    cmp ah,90h
    je .move
.chain:
    jmp far [cs:int1f_previous]
.move:
    push eax
    smsw ax
    test al,1
    pop eax
    jnz .chain
    push bp
    mov bp,sp                       ; [bp+2] IP, [bp+4] CS, [bp+6] FLAGS
    pushad
    push ds
    push es
    push fs
    push gs
    cli
    movzx ecx,cx
    test ecx,ecx
    jnz .count
    mov ecx,10000h
.count:
    ; source/destination linear addresses and limit checks
    movzx eax,word [es:bx+10h]      ; source limit
    inc eax
    movzx edx,si
    add edx,ecx
    cmp edx,eax
    ja .fail
    movzx eax,word [es:bx+18h]      ; destination limit
    inc eax
    movzx edx,di
    add edx,ecx
    cmp edx,eax
    ja .fail
    mov eax,[es:bx+12h]
    and eax,0ffffffh
    movzx esi,si
    add esi,eax
    mov eax,[es:bx+1ah]
    and eax,0ffffffh
    movzx edi,di
    add edi,eax
    ; A20: remember the state, enable for the copy
    call int1f_a20_state
    mov [cs:int1f_a20],al
    out 0f2h,al
    ; protected mode, flat data, copy, back with 64 KiB real-mode limits
    sgdt [cs:int1f_old_gdtr]
    lgdt [cs:int1f_gdtr]
    mov eax,cr0
    or al,1
    mov cr0,eax
    jmp 08h:.pm
.pm:
    mov ax,10h
    mov ds,ax
    mov es,ax
    cld
    mov edx,ecx
    shr ecx,2
    a32 rep movsd
    mov ecx,edx
    and ecx,3
    a32 rep movsb
    mov ax,18h
    mov ds,ax
    mov es,ax
    mov fs,ax
    mov gs,ax
    mov eax,cr0
    and al,0feh
    mov cr0,eax
    jmp RESIDENT_SEGMENT:.rm
.rm:
    lgdt [cs:int1f_old_gdtr]
    cmp byte [cs:int1f_a20],0
    jne .done
    mov al,3                        ; A20 was off: switch it off again
    out 0f6h,al
.done:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    and word [bp+6],0fffeh
    pop bp
    iret
.fail:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    or word [bp+6],1
    pop bp
    iret
; AL = 1 when A20 is on (0000:0080 and FFFF:0090 differ, or stop aliasing).
int1f_a20_state:
    push ds
    push es
    xor ax,ax
    mov ds,ax
    dec ax
    mov es,ax
    mov ax,[ds:80h]
    cmp ax,[es:90h]
    jne .on
    not word [ds:80h]
    mov ax,[ds:80h]
    cmp ax,[es:90h]
    not word [ds:80h]
    je .off
.on:
    mov al,1
    jmp .out
.off:
    xor al,al
.out:
    pop es
    pop ds
    ret
int1f_a20: db 0
align 8
int1f_gdt:
    dq 0
    dq 00009A0D8000FFFFh + 0          ; 08h code16, base D8000h (this segment)
    dq 00CF92000000FFFFh              ; 10h data, flat 4 GB
    dq 000092000000FFFFh              ; 18h data16, 64 KiB (real-mode limits)
int1f_gdtr: dw 4*8-1
    dd RESIDENT_SEGMENT*16 + int1f_gdt
int1f_old_gdtr: dw 0
    dd 0

geometries: db 8,17, 8,32, 16,63, 16,32, 8,63, 4,17, 16,17, 8,33, 8,25, 4,32, 2,17, 0,0
error_text: db 'Zet98: VHD boot failed. Use a raw 512-byte-sector PC-98 DOS image.',0
%include "software/pc98_ide_read_bios.inc"
%if ($-$$) > 4000h
%error Resident BIOS overlaps scratch sectors
%endif
