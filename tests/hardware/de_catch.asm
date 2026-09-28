; SPDX-License-Identifier: GPL-3.0-or-later
; DECATCH.COM: resident INT 0 (divide error) recorder for game crashes.
;   DECATCH      install; the first #DE saves CS:IP, registers, 16 code bytes
;                and 16 stack words, then chains to the previous handler
;   DECATCH S    show the saved record (text lines)
; The record sits at a fixed offset in the resident copy, found through the
; INT 0 vector (segment) and a signature.
        cpu     386
        org     100h
bits 16
start:  jmp     main

; ---- resident part ----
sig:    db      'DECATCH1'
old0:   dd      0
count:  dw      0
rec:                            ; filled on the first fault
r_ip:   dw      0
r_cs:   dw      0
r_fl:   dw      0
r_ax:   dd      0
r_bx:   dd      0
r_cx:   dd      0
r_dx:   dd      0
r_si:   dw      0
r_di:   dw      0
r_bp:   dw      0
r_sp:   dw      0
r_ds:   dw      0
r_es:   dw      0
r_ss:   dw      0
r_code: times 16 db 0
r_stk:  times 16 dw 0
rec_end:

int0:   inc     word [cs:count]
        cmp     word [cs:count], 1
        jne     .chain
        mov     [cs:r_ax], eax
        mov     [cs:r_bx], ebx
        mov     [cs:r_cx], ecx
        mov     [cs:r_dx], edx
        mov     [cs:r_si], si
        mov     [cs:r_di], di
        mov     [cs:r_bp], bp
        mov     [cs:r_ds], ds
        mov     [cs:r_es], es
        mov     [cs:r_ss], ss
        push    bp
        mov     bp, sp
        lea     ax, [bp+8]              ; SP before the fault
        mov     [cs:r_sp], ax
        mov     ax, [bp+2]
        mov     [cs:r_ip], ax
        mov     ax, [bp+4]
        mov     [cs:r_cs], ax
        mov     ax, [bp+6]
        mov     [cs:r_fl], ax
        push    ds
        push    es
        push    si
        push    di
        push    cx
        push    cs
        pop     es
        mov     ds, [bp+4]
        mov     si, [bp+2]
        mov     di, r_code
        mov     cx, 16
        rep     movsb
        mov     ax, ss
        mov     ds, ax
        lea     si, [bp+8]
        mov     di, r_stk
        mov     cx, 16
        rep     movsw
        pop     cx
        pop     di
        pop     si
        pop     es
        pop     ds
        mov     eax, [cs:r_ax]
        pop     bp
.chain: jmp     far [cs:old0]
resident_end:

; ---- transient part ----
main:   mov     si, 81h
.skip:  lodsb
        cmp     al, ' '
        je      .skip
        and     al, 0DFh
        cmp     al, 'S'
        je      show
        ; install
        mov     ax, 3500h
        int     21h
        mov     [old0], bx
        mov     [old0+2], es
        mov     dx, int0
        mov     ax, 2500h
        int     21h
        mov     dx, msg_inst
        mov     ah, 9
        int     21h
        mov     dx, (resident_end - start + 100h + 15) / 16
        mov     ax, 3100h
        int     21h

show:   mov     ax, 3500h
        int     21h
        mov     di, sig
        mov     si, sig
        mov     cx, 8
        repe    cmpsb                  ; ES:DI resident vs DS:SI ours
        je      .found
        mov     dx, msg_none
        mov     ah, 9
        int     21h
        ret
.found: push    es
        pop     fs                     ; FS = resident segment
        mov     dx, t_head
        call    puts
        mov     ax, [fs:count]
        call    phexw
        call    crlf
        cmp     word [fs:count], 0
        je      .done
        ; CS:IP FL
        mov     dx, t_csip
        call    puts
        mov     ax, [fs:r_cs]
        call    phexw
        mov     dl, ':'
        call    putc
        mov     ax, [fs:r_ip]
        call    phexw
        mov     dx, t_fl
        call    puts
        mov     ax, [fs:r_fl]
        call    phexw
        call    crlf
        ; 32-bit registers
        mov     dx, t_eax
        call    puts
        mov     eax, [fs:r_ax]
        call    phexd
        mov     dx, t_ebx
        call    puts
        mov     eax, [fs:r_bx]
        call    phexd
        mov     dx, t_ecx
        call    puts
        mov     eax, [fs:r_cx]
        call    phexd
        mov     dx, t_edx
        call    puts
        mov     eax, [fs:r_dx]
        call    phexd
        call    crlf
        ; 16-bit registers and segments
        mov     bx, seglist
.segs:  mov     dx, [bx]
        or      dx, dx
        jz      .code
        call    puts
        mov     di, [bx+2]
        mov     ax, [fs:di]
        call    phexw
        add     bx, 4
        jmp     .segs
.code:  call    crlf
        mov     dx, t_code
        call    puts
        mov     si, r_code
        mov     cx, 16
.cb:    mov     al, [fs:si]
        call    phexb
        mov     dl, ' '
        call    putc
        inc     si
        loop    .cb
        call    crlf
        mov     dx, t_stk
        call    puts
        mov     si, r_stk
        mov     cx, 16
.sw:    mov     ax, [fs:si]
        call    phexw
        mov     dl, ' '
        call    putc
        add     si, 2
        loop    .sw
        call    crlf
.done:  ret

puts:   mov     ah, 9
        int     21h
        ret
putc:   mov     ah, 2
        int     21h
        ret
crlf:   mov     dl, 13
        call    putc
        mov     dl, 10
        jmp     putc
phexd:  push    eax
        shr     eax, 16
        call    phexw
        pop     eax
phexw:  push    ax
        mov     al, ah
        call    phexb
        pop     ax
phexb:  push    ax
        shr     al, 4
        call    .nib
        pop     ax
.nib:   push    ax
        and     al, 0Fh
        add     al, '0'
        cmp     al, '9'
        jbe     .p
        add     al, 7
.p:     mov     dl, al
        call    putc
        pop     ax
        ret

msg_inst: db 'DECATCH installed (INT 0 recorder). DECATCH S shows the record.', 13, 10, '$'
msg_none: db 'DECATCH is not the current INT 0 handler.', 13, 10, '$'
t_head:   db 'DECATCH: divide faults $'
t_csip:   db 'first CS:IP=$'
t_fl:     db ' FL=$'
t_eax:    db 'EAX=$'
t_ebx:    db ' EBX=$'
t_ecx:    db ' ECX=$'
t_edx:    db ' EDX=$'
t_code:   db 'code: $'
t_stk:    db 'stack: $'
s_si:     db 'SI=$'
s_di:     db ' DI=$'
s_bp:     db ' BP=$'
s_sp:     db ' SP=$'
s_ds:     db ' DS=$'
s_es:     db ' ES=$'
s_ss:     db ' SS=$'
seglist:  dw s_si, r_si, s_di, r_di, s_bp, r_bp, s_sp, r_sp
          dw s_ds, r_ds, s_es, r_es, s_ss, r_ss, 0
