; SPDX-License-Identifier: GPL-3.0-or-later
; Experimental PC-98 INT 1Bh read service for the raw ATA master.
; Not an option-ROM header, installer or boot loader. The embedding program
; must provide bios_previous_vector (far pointer), and set the image geometry.
; Caller ABI follows NP2kai bios/sxsibios.c: AL=80h CHS (zero-based sector),
; AL=00h linear DL:CX, BX byte count (0=64K), ES:BP buffer, AH low nibble command.
; Only drive zero is intercepted; other devices chain to the previous handler.
; Default builds reject writes. BIOS_ALLOW_WRITES requires an explicit inclusive
; LBA write window; use a disposable image until the embedding BIOS is tested.
bits 16
cpu 386
%ifndef BIOS_HEADS
%error Define BIOS_HEADS, BIOS_SECTORS and BIOS_CYLINDERS for the image
%endif
%ifndef BIOS_POLL_LIMIT
%define BIOS_POLL_LIMIT 1000000
%endif
%define BIOS_TOTAL (BIOS_HEADS * BIOS_SECTORS * BIOS_CYLINDERS)
%ifdef BIOS_ALLOW_WRITES
%ifndef BIOS_WRITE_FIRST_LBA
%error Define an explicit BIOS_WRITE_FIRST_LBA / BIOS_WRITE_LAST_LBA window
%endif
%ifndef BIOS_WRITE_LAST_LBA
%error Define an explicit BIOS_WRITE_FIRST_LBA / BIOS_WRITE_LAST_LBA window
%endif
%if BIOS_WRITE_FIRST_LBA < 0 || BIOS_WRITE_LAST_LBA < BIOS_WRITE_FIRST_LBA || BIOS_WRITE_LAST_LBA >= BIOS_TOTAL
%error Write window is outside the configured image
%endif
%endif
%if BIOS_HEADS < 1 || BIOS_HEADS > 255 || BIOS_SECTORS < 1 || BIOS_SECTORS > 255 || BIOS_CYLINDERS < 1 || BIOS_CYLINDERS > 65535 || BIOS_TOTAL > 0x10000000
%error Geometry is outside the supported PC-98/LBA28 range
%endif

bios_int1b:
    push ds
    push es
    pushad
    xor ebp,ebp
    mov bp,sp
    ; Stack: EDI 0, ESI 4, EBP 8, ESP 12, EBX 16, EDX 20,
    ; ECX 24, EAX 28, ES 32, DS 34, return IP 36, CS 38, FLAGS 40.
    cmp byte [ss:bp+28],80h
    je .selected
    cmp byte [ss:bp+28],0
    je .selected
    popad
    pop es
    pop ds
    jmp far [cs:bios_previous_vector]
.selected:
    cld
    mov al,[ss:bp+29]
    and al,0fh
    cmp al,3
    je .initialize
    cmp al,4
    je .sense
    cmp al,5
%ifdef BIOS_ALLOW_WRITES
    je .position
%else
    je .protected
%endif
    cmp al,7
    je .success
    cmp al,0fh
    je .success
    cmp al,1
    je .position
    cmp al,6
    jne .unsupported
.position:
    movzx esi,word [ss:bp+24]
    test byte [ss:bp+28],80h
    jz .linear
    cmp esi,BIOS_CYLINDERS
    jae .range
    movzx eax,byte [ss:bp+21]
    cmp eax,BIOS_HEADS
    jae .range
    imul esi,BIOS_HEADS
    add esi,eax
    imul esi,BIOS_SECTORS
    movzx eax,byte [ss:bp+20]
    cmp eax,BIOS_SECTORS
    jae .range
    add esi,eax
    jmp .length
.linear:
    movzx eax,byte [ss:bp+20]
    shl eax,16
    or esi,eax
.length:
    movzx ebx,word [ss:bp+16]
    test ebx,ebx
    jnz .nonzero
    mov ebx,65536
.nonzero:
    mov eax,ebx
    add eax,511
    shr eax,9
    add eax,esi
    cmp eax,BIOS_TOTAL
    ja .range
%ifdef BIOS_ALLOW_WRITES
    mov dl,[ss:bp+29]
    and dl,0fh
    cmp dl,5
    jne .buffer_range
    cmp esi,BIOS_WRITE_FIRST_LBA
    jb .protected
    cmp eax,BIOS_WRITE_LAST_LBA+1
    ja .protected
.buffer_range:
%endif
    movzx edi,word [ss:bp+32]
    shl edi,4
    movzx eax,word [ss:bp+8]
    add edi,eax
    mov eax,edi
    add eax,ebx
    cmp eax,100000h
    ja .range
    ; Use a stack bounce buffer: the service itself can later reside in ROM.
    sub sp,512
    mov dx,0432h
    xor al,al
    out dx,al
    mov dx,074ch
    mov al,2                 ; polled PIO; no pending IRQ is left on return
    out dx,al
.sector:
    call bios_wait_idle
    jc .io_failed
%ifdef BIOS_ALLOW_WRITES
    mov al,[ss:bp+29]
    and al,0fh
    cmp al,5
    jne .read_sector
    ; A partial final write first reads its sector to preserve the tail.
    cmp ebx,512
    jae .write_sector
.read_sector:
%endif
    call bios_program_sector
    mov al,20h
    out dx,al
    call bios_wait_data
    jc .io_failed
    push esi
    push edi
    push ss
    pop es
    lea di,[bp-512]
    mov cx,256
    mov dx,0640h
    rep insw
    pop edi
    pop esi
    mov dx,064eh
    in al,dx                 ; acknowledge ATA interrupt latch
    test al,21h              ; ERR or device fault
    jnz .io_failed
    mov al,[ss:bp+29]
    and al,0fh
%ifdef BIOS_ALLOW_WRITES
    cmp al,5
    je .write_sector
%endif
    cmp al,1                 ; VERIFY reads the sector but leaves memory alone
    je .advance
    push esi
    push edi
    push ss
    pop ds
    lea si,[bp-512]
    mov eax,edi
    shr eax,4
    mov es,ax
    and di,15
    mov ecx,ebx
    cmp ecx,512
    jbe .copy
    mov cx,512
.copy:
    rep movsb
    pop edi
    pop esi
%ifdef BIOS_ALLOW_WRITES
    jmp .advance
.write_sector:
    ; Copy from the caller's physical buffer into the stack bounce buffer.
    ; Normalizing DS:SI per sector also handles a caller's 64K offset wrap.
    push esi
    push edi
    mov eax,edi
    shr eax,4
    mov ds,ax
    mov esi,edi
    and si,15
    push ss
    pop es
    lea di,[bp-512]
    mov ecx,ebx
    cmp ecx,512
    jbe .write_copy
    mov cx,512
.write_copy:
    rep movsb
    pop edi
    pop esi
    call bios_wait_idle
    jc .io_failed
    call bios_program_sector
    mov al,30h
    out dx,al
    call bios_wait_data
    jc .io_failed
    push esi
    push ss
    pop ds
    lea si,[bp-512]
    mov cx,256
    mov dx,0640h
    rep outsw
    pop esi
    call bios_wait_write_complete
    jc .io_failed
%endif
.advance:
    mov eax,ebx
    cmp eax,512
    jbe .last
    mov eax,512
.last:
    add edi,eax
    sub ebx,eax
    inc esi
    test ebx,ebx
    jnz .sector
    add sp,512
    call bios_end_pio
    jmp .success
.io_failed:
    add sp,512
    call bios_end_pio
    mov al,60h
    jmp .return
.initialize:
    xor ax,ax
    mov ds,ax
    and word [055ch],0feffh
    call bios_present
    jc .not_ready
    or word [055ch],0100h
    jmp .success
.sense:
    call bios_present
    jc .not_ready
    cmp byte [ss:bp+29],84h
    jne .sense_done
    mov word [ss:bp+16],512
    mov word [ss:bp+24],BIOS_CYLINDERS
    mov word [ss:bp+20],(BIOS_HEADS << 8) | BIOS_SECTORS
.sense_done:
    mov al,0fh
    jmp .return
.not_ready:
    mov al,60h
    jmp .return
.protected:
    mov al,70h
    jmp .return
.range:
    mov al,0d0h
    jmp .return
.unsupported:
    mov al,40h
    jmp .return
.success:
    xor al,al
.return:
    mov [ss:bp+29],al
    and word [ss:bp+40],0fffeh
    cmp al,20h
    jb .restore
    or word [ss:bp+40],1
.restore:
    popad
    pop es
    pop ds
    iret

bios_program_sector:
    mov eax,esi
    shr eax,24
    or al,0e0h
    mov dx,064ch
    out dx,al
    mov dx,0644h
    mov al,1
    out dx,al
    mov eax,esi
    mov dx,0646h
    out dx,al
    shr eax,8
    add dx,2
    out dx,al
    shr eax,8
    add dx,2
    out dx,al
    mov dx,064eh
    ret

%ifdef BIOS_ALLOW_WRITES
bios_wait_write_complete:
    mov ecx,BIOS_POLL_LIMIT
    mov dx,074ch
.poll:
    in al,dx
    test al,80h
    jnz .again
    test al,21h
    jnz .failed
    test al,8
    jnz .again
    test al,40h
    jz .failed
    clc
    ret
.again:
    dec ecx
    jnz .poll
.failed:
    stc
    ret
%endif

bios_present:
    mov dx,0432h
    xor al,al
    out dx,al
    ; Continue with the bounded ready poll.
bios_wait_idle:
    mov ecx,BIOS_POLL_LIMIT
    mov dx,074ch
.poll:
    in al,dx
    test al,80h
    jz .ready
    dec ecx
    jnz .poll
    stc
    ret
.ready:
    ; Empty/unplugged buses must not count as ready.
    test al,40h
    jz .absent
    clc
    ret
.absent:
    stc
    ret

bios_wait_data:
    mov ecx,BIOS_POLL_LIMIT
    mov dx,074ch
.poll:
    in al,dx
    test al,80h
    jnz .again
    test al,21h
    jnz .failed
    test al,8
    jnz .ready
.again:
    dec ecx
    jnz .poll
.failed:
    stc
    ret
.ready:
    clc
    ret

bios_end_pio:
    mov dx,064eh
    in al,dx
    mov dx,074ch
    xor al,al
    out dx,al
    ret
