; SPDX-License-Identifier: GPL-3.0-or-later
; VRAMBENCH.COM: CPU throughput to PC-98 memory and graphics VRAM, timed with
; the 307.2 kHz ARTIC counter (ports 5Ch/5Eh). Prints KB/s per test:
;   RAM W     REP STOSW 32 KB to conventional RAM (baseline)
;   VRAM W    REP STOSW 32 KB to graphics plane B (A800:0000)
;   VRAM R    REP LODSW 32 KB from plane B
;   GRCG TDW  REP STOSW 32 KB through the GRCG tile-write mode (all planes)
;   VRAM MOV  REP MOVSW 16 KB plane B -> plane B (overlapping halves)
;   RAM W32   REP STOSD 32 KB to conventional RAM
;   RAM R32   REP LODSD 32 KB from conventional RAM
;   EXT W32   A32 REP STOSD 256 KB at 8 MB (extended RAM, unreal mode)
;   EXT R32   A32 REP LODSD 256 KB at 8 MB
;   MIX RAM   KB/s of STOSW with 6 register instructions between stores (RAM)
;   MIX VRAM  the same loop to plane B (posted writes overlap the ALU work)
;   OUT 4A2   ns per OUT DX,AX to the EGC read/write-plane register (EGC off)
;   IN 0A0    ns per IN AL,0A0h (graphics GDC status)
;   OUT 5F    ns per OUT 5Fh (the architectural 0.6 us wait port)
; Extended tests need A20 on (HIMEM.SYS) and no EMM386/V86 mode.
; Each test repeats 8 times. Graphics display is left as it was (the planes
; get patterns); run from a text prompt.
        cpu     386
        org     100h
bits 16
start:  cld
        mov     dx, title
        call    puts
        ; RAM target: the segment 64 KB above this program
        mov     ax, cs
        add     ax, 1000h
        mov     [ramseg], ax

        mov     dx, t_ramw
        call    puts
        mov     es, [ramseg]
        mov     bx, 16384               ; words
        call    bench_stosw
        call    report

        mov     dx, t_vramw
        call    puts
        mov     ax, 0A800h
        mov     es, ax
        mov     bx, 16000
        call    bench_stosw
        call    report

        mov     dx, t_vramr
        call    puts
        mov     ax, 0A800h
        mov     ds, ax
        mov     bx, 16000
        call    bench_lodsw
        push    cs
        pop     ds
        call    report

        mov     dx, t_grcg
        call    puts
        mov     al, 80h                 ; GRCG on, TDW mode, all planes
        out     7Ch, al
        mov     cx, 4
.tiles: mov     al, 0AAh
        out     7Eh, al
        loop    .tiles
        mov     ax, 0A800h
        mov     es, ax
        mov     bx, 16000
        call    bench_stosw
        xor     al, al
        out     7Ch, al                 ; GRCG off
        call    report

        mov     dx, t_move
        call    puts
        mov     ax, 0A800h
        mov     ds, ax
        mov     es, ax
        mov     bx, 8000
        call    bench_movsw
        push    cs
        pop     ds
        call    report

        mov     dx, t_ramw32
        call    puts
        mov     es, [ramseg]
        mov     bx, 8192                ; dwords
        call    bench_stosd
        call    report

        mov     dx, t_ramr32
        call    puts
        mov     ds, [ramseg]
        mov     bx, 8192
        call    bench_lodsd
        push    cs
        pop     ds
        call    report

        mov     dx, t_mixram
        call    puts
        mov     es, [ramseg]
        call    bench_mix
        call    report
        mov     dx, t_mixvram
        call    puts
        mov     ax, 0A800h
        mov     es, ax
        call    bench_mix
        call    report

        mov     dx, t_out4a2
        call    puts
        mov     dx, 04A2h
        mov     ax, 00FFh
        mov     di, 1                   ; 1 = OUT DX,AX
        call    bench_io
        call    report_ns
        mov     dx, t_in0a0
        call    puts
        mov     dx, 00A0h
        mov     di, 2                   ; 2 = IN AL,DX
        call    bench_io
        call    report_ns
        mov     dx, t_out5f
        call    puts
        mov     dx, 005Fh
        xor     ax, ax
        mov     di, 3                   ; 3 = OUT DX,AL
        call    bench_io
        call    report_ns

        smsw    ax                      ; V86/protected mode: skip extended tests
        test    al, 1
        jnz     .done
        call    unreal
        mov     dx, t_extw
        call    puts
        call    bench_ext_stosd
        call    report
        mov     dx, t_extr
        call    puts
        call    bench_ext_lodsd
        call    report
.done:  mov     ax, 4C00h
        int     21h

; Flat 4 GB limits for DS/ES (unreal mode), then ES=DS=CS again with bases
; reloaded in real mode; the extended kernels use ES/DS = 0 with a32.
unreal: cli
        mov     eax, cs
        shl     eax, 4
        add     eax, gdt
        mov     [gdtr+2], eax
        lgdt    [gdtr]
        mov     eax, cr0
        or      al, 1
        mov     cr0, eax
        jmp     short .pm
.pm:    mov     bx, 8
        mov     ds, bx
        mov     es, bx
        and     al, 0FEh
        mov     cr0, eax
        jmp     short .rm
.rm:    push    cs
        pop     ds
        push    cs
        pop     es
        sti
        ret

bench_ext_stosd:
        mov     dword [bytes], 8*65536*4
        call    ticks
        mov     [t0], eax
        xor     ax, ax
        mov     es, ax
        mov     bp, 8
.r:     mov     edi, 800000h
        mov     ecx, 65536
        mov     eax, 5A5A5A5Ah
        a32 rep stosd
        dec     bp
        jnz     .r
        push    cs
        pop     es
        jmp     elapsed

bench_ext_lodsd:
        mov     dword [bytes], 8*65536*4
        call    ticks
        mov     [t0], eax
        xor     ax, ax
        mov     ds, ax
        mov     bp, 8
.r:     mov     esi, 800000h
        mov     ecx, 65536
        a32 rep lodsd
        dec     bp
        jnz     .r
        push    cs
        pop     ds
        jmp     elapsed

; 8 x 16000 word stores, each followed by six dependent register ops
bench_mix:
        mov     dword [bytes], 8*16000*2
        call    ticks
        mov     [t0], eax
        mov     bp, 8
.r:     xor     di, di
        mov     cx, 16000
        mov     ax, 1234h
        mov     bx, 5678h
.l:     stosw
        add     ax, bx
        xor     bx, ax
        rol     ax, 1
        add     bx, 3
        xor     ax, 0A5A5h
        sub     bx, ax
        loop    .l
        dec     bp
        jnz     .r
        jmp     elapsed

; 20000 accesses of the kind in DI to port DX; EAX = ARTIC ticks
bench_io:
        push    ax
        call    ticks
        mov     [t0], eax
        pop     ax
        mov     cx, 20000
        cmp     di, 2
        je      .in
        cmp     di, 3
        je      .out8
.o16:   out     dx, ax
        loop    .o16
        jmp     elapsed
.in:    in      al, dx
        loop    .in
        jmp     elapsed
.out8:  out     dx, al
        loop    .out8
        jmp     elapsed

; ns per access = ticks * 3255 / 20000 (ARTIC tick = 3.255 us)
report_ns:
        push    cs
        pop     ds
        mov     edx, 3255
        mul     edx
        mov     ecx, 20000
        div     ecx
        call    putdec
        mov     dx, nsop
        call    puts
        ret

bench_stosd:
        movzx   eax, bx
        shl     eax, 5                  ; 8 reps * 4 bytes
        mov     [bytes], eax
        call    ticks
        mov     [t0], eax
        mov     bp, 8
.r:     xor     di, di
        mov     cx, bx
        mov     eax, 5A5A5A5Ah
        rep     stosd
        dec     bp
        jnz     .r
        jmp     elapsed

bench_lodsd:
        movzx   eax, bx
        shl     eax, 5
        mov     [cs:bytes], eax
        call    ticks
        mov     [cs:t0], eax
        mov     bp, 8
.r:     xor     si, si
        mov     cx, bx
        rep     lodsd
        dec     bp
        jnz     .r
        jmp     elapsed

; --- timed kernels (8 repetitions); result: EAX = ARTIC ticks, bytes in [bytes]
bench_stosw:
        movzx   eax, bx
        shl     eax, 4                  ; 8 reps * 2 bytes
        mov     [bytes], eax
        call    ticks
        mov     [t0], eax
        mov     bp, 8
.r:     xor     di, di
        mov     cx, bx
        mov     ax, 5A5Ah
        rep     stosw
        dec     bp
        jnz     .r
        jmp     elapsed

bench_lodsw:
        movzx   eax, bx
        shl     eax, 4
        mov     [cs:bytes], eax
        call    ticks
        mov     [cs:t0], eax
        mov     bp, 8
.r:     xor     si, si
        mov     cx, bx
        rep     lodsw
        dec     bp
        jnz     .r
        jmp     elapsed

bench_movsw:
        movzx   eax, bx
        shl     eax, 4
        mov     [cs:bytes], eax
        call    ticks
        mov     [cs:t0], eax
        mov     bp, 8
.r:     mov     si, 16000
        xor     di, di
        mov     cx, bx
        rep     movsw
        dec     bp
        jnz     .r
        ; fall through
elapsed:
        call    ticks
        sub     eax, [cs:t0]
        and     eax, 0FFFFFFh           ; 24-bit counter wrap
        ret

; 24-bit ARTIC counter: 5Ch = bits 0-15, 5Eh = bits 8-23. Read 5Eh, 5Ch,
; 5Eh and retry if the upper part changed in between.
ticks:  push    dx
        push    bx
.again: in      ax, 5Eh
        mov     bx, ax
        in      ax, 5Ch
        mov     dx, ax
        in      ax, 5Eh
        cmp     ax, bx
        jne     .again
        movzx   eax, bh                 ; bits 16-23
        shl     eax, 16
        mov     ax, dx
        pop     bx
        pop     dx
        ret

; print KB/s = bytes * 307200 / ticks / 1024 = bytes * 300 / ticks
report: push    cs
        pop     ds
        mov     ecx, eax
        test    ecx, ecx
        jnz     .ok
        inc     ecx
.ok:    mov     eax, [bytes]
        mov     edx, 300
        mul     edx                     ; EDX:EAX = bytes*300
        div     ecx
        call    putdec
        mov     dx, kbs
        call    puts
        ret

putdec: mov     ebx, 10
        xor     cx, cx
.d:     xor     edx, edx
        div     ebx
        push    dx
        inc     cx
        test    eax, eax
        jnz     .d
.p:     pop     dx
        add     dl, '0'
        mov     ah, 2
        int     21h
        loop    .p
        ret

puts:   mov     ah, 9
        int     21h
        ret

title   db 'VRAMBENCH (KB/s, ARTIC timed)', 13, 10, '$'
t_ramw  db 'RAM W     $'
t_vramw db 'VRAM W    $'
t_vramr db 'VRAM R    $'
t_grcg  db 'GRCG TDW  $'
t_move  db 'VRAM MOV  $'
t_ramw32 db 'RAM W32   $'
t_ramr32 db 'RAM R32   $'
t_extw  db 'EXT W32   $'
t_extr  db 'EXT R32   $'
t_mixram db 'MIX RAM   $'
t_mixvram db 'MIX VRAM  $'
t_out4a2 db 'OUT 4A2   $'
t_in0a0 db 'IN 0A0    $'
t_out5f db 'OUT 5F    $'
nsop    db ' ns/op (incl. loop)', 13, 10, '$'
kbs     db ' KB/s', 13, 10, '$'
ramseg  dw 0
t0      dd 0
bytes   dd 0
        align 8
gdt     dq 0
        dq 00CF92000000FFFFh            ; flat data, 4 GB, 32-bit
gdtr    dw 15
        dd 0
