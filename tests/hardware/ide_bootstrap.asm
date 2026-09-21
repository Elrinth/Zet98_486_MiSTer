; SPDX-License-Identifier: GPL-3.0-or-later
; Private-image boot experiment for this core ONLY, not a PC-98 option ROM.
; D8000-DFFFF is ordinary RAM in this core's current memory map. This test
; places its read-only BIOS and stack there, then enters the supplied IPL.
; Do not use on physical PC-98s, with an upper-memory manager, or another map.
; Geometry/checksum identify the owner's prepared DOS 6.20 game VHD.
bits 16
cpu 386
org 100h
%define BIOS_HEADS 8
%define BIOS_SECTORS 17
%define BIOS_CYLINDERS 8162
%define RESIDENT_SEGMENT 0d800h

%ifdef BIOS_BOOT
; Entered directly by our floppy IPL, before any DOS has installed RAM
; interrupt hooks or device drivers. Already loaded at D800:0100.
start:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,07ffeh
    mov ds,ax
    xor ax,ax
    mov es,ax
    mov ax,[es:1bh*4]
    mov [bios_previous_vector],ax
    mov ax,[es:1bh*4+2]
    mov [bios_previous_vector+2],ax
    movzx eax,word [bios_previous_vector+2]
    shl eax,4
    movzx edx,word [bios_previous_vector]
    add eax,edx
    cmp eax,0e8000h
    jb boot_return
    cmp eax,100000h
    jae boot_return
    jmp relocated
%else
start:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,0fffeh
    mov ds,ax
    cld
    sti
    mov ax,351bh
    int 21h
    mov [bios_previous_vector],bx
    mov [bios_previous_vector+2],es
    mov dx,vector_label
    mov ah,9
    int 21h
    mov ax,[bios_previous_vector+2]
    call print_hex
    mov dl,':'
    mov ah,2
    int 21h
    mov ax,[bios_previous_vector]
    call print_hex
    ; A DOS-resident chained handler could be destroyed by the new OS load.
    ; Compare the physical address: noncanonical segment:offset pairs can
    ; point into ROM even when their segment alone is below E800h.
    movzx eax,word [bios_previous_vector+2]
    shl eax,4
    movzx edx,word [bios_previous_vector]
    add eax,edx
    cmp eax,0e8000h
    jb try_dos_wrapper
    cmp eax,100000h
    jae unsafe_vector
    jmp vector_ready
try_dos_wrapper:
    ; The supplied DOS 3.30 disk hooks only its 2DD floppy case:
    ; PUSH AX / AND AL,78h / CMP AL,70h / POP AX / JZ +5 / JMP FAR ROM.
    ; Match every opcode before taking that far target. Do not scan unknown
    ; DOS code for arbitrary far jumps or retain a RAM handler across boot.
    les si,[bios_previous_vector]
    cmp word [es:si],2450h
    jne unsafe_vector
    cmp word [es:si+2],3c78h
    jne unsafe_vector
    cmp word [es:si+4],5870h
    jne unsafe_vector
    cmp word [es:si+6],0574h
    jne unsafe_vector
    cmp byte [es:si+8],0eah
    jne unsafe_vector
    movzx eax,word [es:si+11]
    shl eax,4
    movzx edx,word [es:si+9]
    add eax,edx
    cmp eax,0e8000h
    jb unsafe_vector
    cmp eax,100000h
    jae unsafe_vector
    mov ax,[es:si+9]
    mov [bios_previous_vector],ax
    mov ax,[es:si+11]
    mov [bios_previous_vector+2],ax
    mov dx,unwrapped_text
    mov ah,9
    int 21h
vector_ready:
    mov dx,start_text
    mov ah,9
    int 21h
    mov ax,RESIDENT_SEGMENT
    mov es,ax
    mov si,100h
    mov di,si
    mov cx,image_end-100h
    rep movsb
    mov si,100h
    mov di,si
    mov cx,image_end-100h
    repe cmpsb
    jne bad_copy
    jmp RESIDENT_SEGMENT:relocated
unsafe_vector:
    ; Read-only diagnostic bytes help identify a DOS hook/trampoline.
    push ds
    lds si,[bios_previous_vector]
    mov cx,16
.dump:
    mov dl,' '
    mov ah,2
    int 21h
    lodsb
    xor ah,ah
    call print_hex
    loop .dump
    pop ds
    mov dx,vector_text
    jmp dos_stop
bad_copy:
    mov dx,copy_text
dos_stop:
    mov ah,9
    int 21h
    cli
.halt:
    hlt
    jmp .halt

print_hex:
    pushad
    mov bx,ax
    mov cx,4
.digit:
    rol bx,4
    mov dl,bl
    and dl,0fh
    add dl,'0'
    cmp dl,'9'
    jbe .emit
    add dl,7
.emit:
    mov ah,2
    int 21h
    loop .digit
    popad
    ret
%endif

relocated:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,07ffeh
    xor ax,ax
    mov ds,ax
    mov word [1bh*4],bios_stack_int1b
    mov word [1bh*4+2],cs
    mov ax,0380h
    int 1bh
    jc boot_return
    mov ax,01fc0h
    mov es,ax
    xor bp,bp
    xor cx,cx
    xor dx,dx
    mov bx,1024
    mov ax,0680h
    int 1bh
    jc boot_return
    xor ax,ax
    xor di,di
    mov cx,512
.checksum:
    rol ax,1
    xor ax,[es:di]
    add di,2
    loop .checksum
    cmp ax,0f270h
    jne boot_return
    mov byte [0584h],80h
    xor ax,ax
    mov es,ax
    cld
    sti
    call 01fc0h:0
boot_return:
    ; The old DOS may already have been overwritten. Render the failure
    ; directly into text RAM rather than calling any old DOS service.
    cli
    push cs
    pop ds
    mov ax,0a000h
    mov es,ax
    xor di,di
    mov si,boot_text
.char:
    lodsb
    test al,al
    jz .halt
    xor ah,ah
    stosw
    mov word [es:di+2000h-2],0e1h
    jmp .char
.halt:
    hlt
    jmp .halt

bios_previous_vector: dd 0
trace_count: dw 0
caller_ss: dw 0
caller_sp: dw 0
caller_ax: dw 0
result_flags: dw 0
resident_handler: dw bios_int1b, RESIDENT_SEGMENT

; The DOS partition IPL uses SS=0, SP=028Eh. Its stack cannot accommodate
; the read service's 512-byte bounce buffer without overwriting the IVT.
; Selected HDD calls therefore use private resident RAM. Hardware INT clears
; IF; the internal IRET retains IF=0 until the caller's original frame is
; restored. Nonselected devices keep the original stack and ROM handler.
bios_stack_int1b:
    cmp al,80h
    je .selected
    test al,al
    jz .selected
    jmp far [cs:bios_previous_vector]
.selected:
    mov [cs:caller_ax],ax
    mov ax,ss
    mov [cs:caller_ss],ax
    mov [cs:caller_sp],sp
    mov ax,cs
    mov ss,ax
    mov sp,06ffeh
    mov ax,[cs:caller_ax]
%ifdef BIOS_TRACE
    call bios_trace_request
%endif
    pushf
    call far [cs:resident_handler]
    pushf
    pop word [cs:result_flags]
    mov [cs:caller_ax],ax
    push ds
    push bp
    mov ds,[cs:caller_ss]
    mov bp,[cs:caller_sp]
    and word [ds:bp+4],0fffeh
    test byte [cs:result_flags],1
    jz .flags_ready
    or word [ds:bp+4],1
.flags_ready:
    pop bp
    pop ds
    mov ss,[cs:caller_ss]
    mov sp,[cs:caller_sp]
    mov ax,[cs:caller_ax]
    iret

; Keep the last request visible without depending on an OS or display BIOS.
; This is test instrumentation, not part of the disk BIOS ABI. All registers
; and flags are restored before entering the real handler.
bios_trace_request:
    pushf
    push ds
    push es
    pushad
    mov bp,sp
    mov ax,0a000h
    mov es,ax
    mov di,160*2
    push cs
    pop ds
    mov si,trace_label
.label:
    lodsb
    test al,al
    jz .values
    xor ah,ah
    stosw
    mov word [es:di+2000h-2],0e1h
    jmp .label
.values:
    inc word [trace_count]
    mov ax,[trace_count]
    call trace_hex
    mov ax,[ss:bp+28]       ; AX command/device
    call trace_hex
    mov ax,[ss:bp+16]       ; BX byte count
    call trace_hex
    mov ax,[ss:bp+24]       ; CX cylinder/linear low word
    call trace_hex
    mov ax,[ss:bp+20]       ; DX head/sector
    call trace_hex
    mov bx,[caller_sp]
    mov ds,[caller_ss]
    mov ax,[bx+2]           ; original caller CS, before private stack switch
    call trace_hex
    mov bx,[cs:caller_sp]
    mov ax,[bx]             ; original caller IP
    call trace_hex
    popad
    pop es
    pop ds
    popf
    ret
trace_hex:
    mov bx,ax
    mov cx,4
.digit:
    rol bx,4
    mov al,bl
    and al,0fh
    add al,'0'
    cmp al,'9'
    jbe .emit
    add al,7
.emit:
    xor ah,ah
    stosw
    mov word [es:di+2000h-2],0e1h
    loop .digit
    mov ax,' '
    stosw
    mov word [es:di+2000h-2],0e1h
    ret
trace_label: db 'VHD count AX BX CX DX CS IP: ',0
vector_label: db 13,10,'Disk handler: $'
unwrapped_text: db 13,10,'Verified DOS 3.30 wrapper; using its ROM handler.',13,10,'$'
start_text: db 13,10,'Zet98 experimental VHD bootstrap (read-only).',13,10,'Loading the private DOS 6.20 disk...',13,10,'$'
vector_text: db 13,10,'Stopped: old disk vector is not in system ROM.',13,10,'$'
copy_text: db 13,10,'Stopped: resident BIOS RAM copy did not verify.',13,10,'$'
boot_text: db 'Zet98 VHD bootstrap stopped: read, image check or IPL return.',0
%include "software/pc98_ide_read_bios.inc"
image_end:
%if image_end-$$ >= 1f00h
%error Bootstrap code exceeds its reserved area
%endif
