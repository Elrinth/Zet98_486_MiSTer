; SPDX-License-Identifier: GPL-3.0-or-later
; EXTBENCH.COM: memory bandwidth on PC-98, extended (XMS) vs conventional RAM.
; Allocates and locks a 4 MB XMS block, enters unreal mode (flat 4 GB ES/FS
; limits, back in real mode) and times 32-bit REP STOSD / LODSD / MOVSD in
; 4 KB chunks. Each test runs until at least RUN_FRAMES vertical syncs (text
; GDC status port 60h bit 5) have passed, interrupts disabled. It then times
; the XMS driver's own move (function 0Bh, 4 KB blocks, interrupts enabled).
; Under EMM386/VEM486 (V86 mode) the unreal tests are skipped.
; Prints KB/s using a 56.42 Hz frame rate (24 kHz 400-line); frames and
; bytes are printed too, so another refresh rate can be corrected for.
        cpu     386
        org     100h
bits 16

%define RUN_FRAMES 120
%define XMS_KB 4096
%define CHUNK 4096

start:  cld
        mov     dx, title
        call    puts
        ; Conventional test buffer: 64 KB, 64 KB above our segment.
        mov     ax, cs
        add     ax, 1000h
        cmp     ax, 9000h
        jae     no_room
        movzx   eax, ax
        shl     eax, 4
        mov     [conv_base], eax
        ; XMS entry, allocate and lock.
        mov     ax, 4300h
        int     2fh
        cmp     al, 80h
        jne     no_xms
        mov     ax, 4310h
        int     2fh
        mov     [xms], bx
        mov     [xms+2], es
        push    cs
        pop     es
        mov     ah, 09h
        mov     dx, XMS_KB
        call    far [xms]
        test    ax, ax
        jz      no_alloc
        mov     [handle], dx
        mov     ah, 0ch
        mov     dx, [handle]
        call    far [xms]
        test    ax, ax
        jz      no_lock
        mov     [ext_base], bx
        mov     [ext_base+2], dx
        mov     byte [locked], 1
        mov     ah, 05h                 ; local A20 enable
        call    far [xms]
        mov     dx, msg_base
        call    puts
        mov     eax, [ext_base]
        call    puthex32
        call    crlf

        smsw    ax
        test    al, 1
        jz      .real
        mov     dx, msg_v86
        call    puts
        jmp     xms_tests
.real:  call    unreal
        ; Extended memory: region 4 MB, copy 2 MB -> 2 MB.
        mov     eax, [ext_base]
        mov     [cur_base], eax
        mov     dword [cur_size], XMS_KB*1024
        mov     dx, lbl_wx
        mov     word [op], op_write
        call    run
        mov     dx, lbl_rx
        mov     word [op], op_read
        call    run
        mov     dword [cur_size], XMS_KB*512
        mov     dx, lbl_cx
        mov     word [op], op_copy
        call    run
        ; Conventional memory: region 64 KB, copy 32 KB -> 32 KB.
        mov     eax, [conv_base]
        mov     [cur_base], eax
        mov     dword [cur_size], 65536
        mov     dx, lbl_wc
        mov     word [op], op_write
        call    run
        mov     dx, lbl_rc
        mov     word [op], op_read
        call    run
        mov     dword [cur_size], 32768
        mov     dx, lbl_cc
        mov     word [op], op_copy
        call    run
xms_tests:
        sti
        ; XMS move conventional -> extended, then extended -> conventional.
        mov     dword [mv_len], CHUNK
        mov     word [mv_src_h], 0
        mov     ax, cs
        add     ax, 1000h
        mov     word [mv_src_off], 0
        mov     [mv_src_off+2], ax
        mov     ax, [handle]
        mov     [mv_dst_h], ax
        mov     dword [mv_dst_off], 0
        mov     dx, lbl_mcx
        call    run_xms
        mov     ax, [handle]
        mov     [mv_src_h], ax
        mov     dword [mv_src_off], 0
        mov     word [mv_dst_h], 0
        mov     ax, cs
        add     ax, 1000h
        mov     word [mv_dst_off], 0
        mov     [mv_dst_off+2], ax
        mov     dx, lbl_mxc
        call    run_xms
        jmp     done

; ---- timing -------------------------------------------------------------
; run: DX = label, [op] = chunk routine, [cur_base]/[cur_size] = region.
run:    call    puts
        cli
        xor     eax, eax
        mov     [bytes], eax
        mov     [frames], eax
        call    sync
        xor     ebp, ebp                ; offset in region
.loop:  mov     edi, [cur_base]
        add     edi, ebp
        call    [op]
        add     dword [bytes], CHUNK
        add     ebp, CHUNK
        cmp     ebp, [cur_size]
        jb      .next
        xor     ebp, ebp
.next:  call    poll
        cmp     dword [frames], RUN_FRAMES
        jb      .loop
        sti
        jmp     report

; run_xms: DX = label; [mv_*] prepared, offsets advance within the block.
run_xms:
        call    puts
        xor     eax, eax
        mov     [bytes], eax
        mov     [frames], eax
        mov     [xoff], eax
        call    sync
.loop:  mov     eax, [xoff]
        cmp     word [mv_src_h], 0
        je      .dst
        mov     [mv_src_off], eax
        jmp     .go
.dst:   mov     [mv_dst_off], eax
.go:    mov     ah, 0bh
        mov     si, mv_len
        call    far [xms]
        test    ax, ax
        jz      xms_fail
        add     dword [bytes], CHUNK
        mov     eax, [xoff]
        add     eax, CHUNK
        cmp     eax, XMS_KB*1024
        jb      .keep
        xor     eax, eax
.keep:  mov     [xoff], eax
        call    poll
        cmp     dword [frames], RUN_FRAMES
        jb      .loop
        ; fall through
report: mov     eax, [bytes]
        shr     eax, 10
        mov     ecx, 5642
        mul     ecx                     ; KB * 56.42 * 100
        mov     ecx, [frames]
        imul    ecx, ecx, 100
        div     ecx
        call    putdec
        mov     dx, msg_kbs
        call    puts
        mov     eax, [bytes]
        call    putdec
        mov     dx, msg_in
        call    puts
        mov     eax, [frames]
        call    putdec
        mov     dx, msg_frames
        call    puts
        ret

; Wait for a rising VSYNC edge; frame counting starts there.
sync:   in      al, 60h
        test    al, 20h
        jnz     sync
.w:     in      al, 60h
        test    al, 20h
        jz      .w
        mov     byte [last], 20h
        ret
poll:   in      al, 60h
        and     al, 20h
        cmp     al, [last]
        je      .same
        mov     [last], al
        test    al, al
        jz      .same
        inc     dword [frames]
.same:  ret

; ---- chunk operations (flat ES/FS, EDI = chunk address) ----------------
op_write:
        push    es
        xor     ax, ax
        mov     es, ax
        mov     eax, 5a5aa5a5h
        mov     ecx, CHUNK/4
        db      67h, 0f3h, 66h, 0abh    ; a32 rep stosd  ES:[EDI]
        pop     es
        ret
op_read:
        push    fs
        xor     ax, ax
        mov     fs, ax
        mov     esi, edi
        mov     ecx, CHUNK/4
        db      64h, 67h, 0f3h, 66h, 0adh ; a32 rep lodsd FS:[ESI]
        pop     fs
        ret
op_copy:                                ; [EDI] -> [EDI + cur_size]
        push    es
        push    fs
        xor     ax, ax
        mov     es, ax
        mov     fs, ax
        mov     esi, edi
        add     edi, [cur_size]
        mov     ecx, CHUNK/4
        db      64h, 67h, 0f3h, 66h, 0a5h ; a32 rep movsd FS:[ESI] -> ES:[EDI]
        pop     fs
        pop     es
        ret

; Unreal mode: load 4 GB limits into ES and FS, return to real mode.
unreal: cli
        xor     eax, eax
        mov     ax, cs
        shl     eax, 4
        add     eax, gdt
        mov     [gdtr+2], eax
        lgdt    [gdtr]
        mov     eax, cr0
        or      al, 1
        mov     cr0, eax
        jmp     short .pm
.pm:    mov     bx, 8
        mov     es, bx
        mov     fs, bx
        and     al, 0feh
        mov     cr0, eax
        jmp     short .rm
.rm:    xor     bx, bx
        mov     fs, bx
        push    cs
        pop     es
        sti
        ret

; ---- exit / errors ------------------------------------------------------
xms_fail:
        mov     dx, msg_xmsfail
        call    puts
done:   cmp     byte [locked], 0
        je      .free
        mov     ah, 0dh
        mov     dx, [handle]
        call    far [xms]
.free:  cmp     word [handle], 0
        je      .out
        mov     ah, 0ah
        mov     dx, [handle]
        call    far [xms]
.out:   sti
        mov     ax, 4c00h
        int     21h
no_room:
        mov     dx, msg_room
        jmp     fail
no_xms: mov     dx, msg_noxms
        jmp     fail
no_alloc:
        mov     dx, msg_alloc
        jmp     fail
no_lock:
        mov     dx, msg_lock
        call    puts
        jmp     done
fail:   call    puts
        mov     ax, 4c01h
        int     21h

; ---- output -------------------------------------------------------------
puts:   mov     ah, 09h
        int     21h
        ret
crlf:   mov     dx, msg_crlf
        jmp     puts
putdec: mov     ebx, 10                 ; EAX unsigned
        xor     cx, cx
.d:     xor     edx, edx
        div     ebx
        push    dx
        inc     cx
        test    eax, eax
        jnz     .d
.p:     pop     dx
        add     dl, '0'
        mov     ah, 02h
        int     21h
        loop    .p
        ret
puthex32:
        mov     cx, 8
.h:     rol     eax, 4
        push    eax
        and     al, 0fh
        add     al, '0'
        cmp     al, '9'
        jbe     .o
        add     al, 7
.o:     mov     dl, al
        mov     ah, 02h
        int     21h
        pop     eax
        loop    .h
        ret

align 8
gdt:    dq      0
        dq      00cf92000000ffffh       ; flat data, 4 GB, byte base 0
gdtr:   dw      15
        dd      0
xms:    dd      0
handle: dw      0
locked: db      0
last:   db      0
ext_base:  dd   0
conv_base: dd   0
cur_base:  dd   0
cur_size:  dd   0
bytes:  dd      0
frames: dd      0
xoff:   dd      0
op:     dw      0
mv_len:     dd  0
mv_src_h:   dw  0
mv_src_off: dd  0
mv_dst_h:   dw  0
mv_dst_off: dd  0

title:  db      'EXTBENCH (PC98-486 memory bandwidth)', 13, 10, '$'
msg_base:   db  'XMS block at physical $'
msg_v86:    db  'V86 mode (EMM386/VEM486): unreal tests skipped', 13, 10, '$'
lbl_wx: db      'Ext  write STOSD : $'
lbl_rx: db      'Ext  read  LODSD : $'
lbl_cx: db      'Ext  copy  MOVSD : $'
lbl_wc: db      'Conv write STOSD : $'
lbl_rc: db      'Conv read  LODSD : $'
lbl_cc: db      'Conv copy  MOVSD : $'
lbl_mcx:    db  'XMS move conv>ext: $'
lbl_mxc:    db  'XMS move ext>conv: $'
msg_kbs:    db  ' KB/s  ($'
msg_in:     db  ' bytes, $'
msg_frames: db  ' frames)', 13, 10, '$'
msg_crlf:   db  13, 10, '$'
msg_room:   db  'Not enough conventional memory', 13, 10, '$'
msg_noxms:  db  'No XMS driver', 13, 10, '$'
msg_alloc:  db  'XMS allocation failed', 13, 10, '$'
msg_lock:   db  'XMS lock failed', 13, 10, '$'
msg_xmsfail: db 'XMS move failed', 13, 10, '$'
