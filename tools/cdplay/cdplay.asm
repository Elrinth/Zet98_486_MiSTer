; SPDX-License-Identifier: GPL-3.0-or-later
; CDPLAY.COM - play one CD audio track through MSCDEX (tests the PC98 core's
; CD audio). Usage: CDPLAY [track]   (default 2)
; Shows the Q-channel position and the driver's busy (playing) bit; any key
; stops playback. Build: nasm -f bin -o CDPLAY.COM cdplay.asm
        cpu     8086
        org     100h

start:  mov     si, 81h                 ; command tail: optional track number
        xor     bx, bx
.skip:  lodsb
        cmp     al, ' '
        je      .skip
.digit: sub     al, '0'
        cmp     al, 9
        ja      .num_done
        mov     ah, bl                  ; bl = bl * 10 + digit
        shl     bl, 1
        shl     ah, 1
        shl     ah, 1
        shl     ah, 1
        add     bl, ah
        add     bl, al
        lodsb
        jmp     .digit
.num_done:
        or      bl, bl
        jnz     .have
        mov     bl, 2
.have:  mov     [track], bl

        mov     ax, 1500h               ; MSCDEX installed / first CD drive
        xor     bx, bx
        int     2Fh
        or      bx, bx
        jnz     .found
        mov     dx, msg_nocd
        jmp     fail
.found: mov     [drive], cx

        mov     byte [cb], 10           ; Audio Disk Info
        mov     cx, 7
        call    ioctl_in
        jc      ioerr
        mov     al, [cb + 1]
        mov     [lowest], al
        mov     al, [cb + 2]
        mov     [highest], al
        mov     ax, [cb + 3]            ; lead-out (Red Book: frame, sec, min, 0)
        mov     [end_addr], ax
        mov     ax, [cb + 5]
        mov     [end_addr + 2], ax
        mov     al, [track]
        cmp     al, [lowest]
        jb      badtrk
        cmp     al, [highest]
        ja      badtrk

        call    track_info              ; start of our track
        jc      ioerr
        test    byte [cb + 6], 40h      ; data track?
        jz      .audio
        mov     dx, msg_data
        jmp     fail
.audio: mov     ax, [cb + 2]
        mov     [start_addr], ax
        mov     ax, [cb + 4]
        mov     [start_addr + 2], ax
        mov     al, [track]
        cmp     al, [highest]
        je      .ends
        inc     al                      ; ends where the next track starts
        mov     [cb + 1], al
        call    track_info_cb
        jc      ioerr
        mov     ax, [cb + 2]
        mov     [end_addr], ax
        mov     ax, [cb + 4]
        mov     [end_addr + 2], ax
.ends:
        mov     si, end_addr
        call    frames
        push    dx
        push    ax
        mov     si, start_addr
        call    frames
        pop     cx                      ; count = end - start
        pop     di
        sub     cx, ax
        sbb     di, dx
        mov     [play_cnt], cx
        mov     [play_cnt + 2], di

        mov     di, req                 ; PLAY AUDIO (132), Red Book address
        call    clear_req
        mov     byte [req], 22
        mov     byte [req + 2], 132
        mov     byte [req + 13], 1
        mov     ax, [start_addr]
        mov     [req + 14], ax
        mov     ax, [start_addr + 2]
        mov     [req + 16], ax
        mov     ax, [play_cnt]
        mov     [req + 18], ax
        mov     ax, [play_cnt + 2]
        mov     [req + 20], ax
        call    dev_req
        test    byte [req + 4], 80h
        jnz     ioerr
        mov     dx, msg_play
        call    print
        mov     al, [track]
        call    hex8
        mov     dx, msg_crlf
        call    print

.loop:  mov     byte [cb], 12           ; Q-channel info
        mov     cx, 11
        call    ioctl_in
        jc      ioerr
        mov     dx, msg_cr
        call    print
        mov     dx, msg_trk
        call    print
        mov     al, [cb + 2]            ; TNO
        call    hex8
        mov     dx, msg_rel
        call    print
        mov     al, [cb + 4]            ; running time in track: min sec
        call    dec2
        mov     dl, ':'
        call    putc
        mov     al, [cb + 5]
        call    dec2
        mov     dx, msg_abs
        call    print
        mov     al, [cb + 8]            ; disc time
        call    dec2
        mov     dl, ':'
        call    putc
        mov     al, [cb + 9]
        call    dec2
        mov     dx, msg_busy            ; busy bit = audio playing
        test    byte [req + 4], 2
        jnz     .b
        mov     dx, msg_idle
.b:     call    print
        test    byte [req + 4], 2
        jz      .done
        mov     ah, 0Bh                 ; key pressed?
        int     21h
        or      al, al
        jz      .loop
        mov     ah, 08h
        int     21h
        mov     di, req                 ; STOP AUDIO (133)
        call    clear_req
        mov     byte [req], 13
        mov     byte [req + 2], 133
        call    dev_req
        mov     dx, msg_stop
        call    print
        jmp     exit
.done:  mov     dx, msg_done
        call    print
exit:   mov     ax, 4C00h
        int     21h

badtrk: mov     dx, msg_badtrk
        jmp     fail
ioerr:  mov     dx, msg_ioerr
fail:   call    print
        mov     ax, 4C01h
        int     21h

; Audio Track Info for [track] -> cb (2-5 start, 6 control)
track_info:
        mov     al, [track]
        mov     [cb + 1], al
track_info_cb:
        mov     byte [cb], 11
        mov     cx, 7
        ; fall through
; IOCTL INPUT of cx bytes into cb; CF on error
ioctl_in:
        push    cx
        mov     di, req
        call    clear_req
        pop     cx
        mov     byte [req], 26
        mov     byte [req + 2], 3
        mov     word [req + 14], cb
        mov     [req + 16], cs
        mov     [req + 18], cx
        call    dev_req
        test    byte [req + 4], 80h
        jz      .ok
        stc
        ret
.ok:    clc
        ret
dev_req:
        push    cs
        pop     es
        mov     bx, req
        mov     cx, [drive]
        mov     ax, 1510h
        int     2Fh
        ret
clear_req:
        push    cs
        pop     es
        mov     cx, 26
        xor     al, al
        cld
        rep     stosb
        ret
; [si] = Red Book (frame, sec, min) -> dx:ax frames
frames: mov     al, [si + 2]
        xor     ah, ah
        mov     bx, 4500
        mul     bx
        mov     cx, ax
        mov     bx, dx
        mov     al, [si + 1]
        xor     ah, ah
        mov     dl, 75
        mul     dl
        add     cx, ax
        adc     bx, 0
        mov     al, [si]
        xor     ah, ah
        add     cx, ax
        adc     bx, 0
        mov     ax, cx
        mov     dx, bx
        ret
print:  mov     ah, 09h
        int     21h
        ret
putc:   mov     ah, 02h
        int     21h
        ret
hex8:   push    ax
        mov     cl, 4
        shr     al, cl
        call    .nib
        pop     ax
        and     al, 0Fh
.nib:   add     al, '0'
        cmp     al, '9'
        jbe     .p
        add     al, 7
.p:     mov     dl, al
        jmp     putc
dec2:   xor     ah, ah                  ; two decimal digits
        mov     bl, 10
        div     bl
        push    ax
        add     al, '0'
        mov     dl, al
        call    putc
        pop     ax
        mov     al, ah
        add     al, '0'
        mov     dl, al
        jmp     putc

msg_nocd   db 'No MSCDEX CD-ROM drive.', 13, 10, '$'
msg_data   db 'That is a data track.', 13, 10, '$'
msg_badtrk db 'No such track.', 13, 10, '$'
msg_ioerr  db 'Driver error.', 13, 10, '$'
msg_play   db 'Playing track $'
msg_trk    db 'Q track $'
msg_rel    db '  track time $'
msg_abs    db '  disc $'
msg_busy   db '  PLAY (any key stops) $'
msg_idle   db '  IDLE                 $'
msg_stop   db 13, 10, 'Stopped.', 13, 10, '$'
msg_done   db 13, 10, 'Track finished.', 13, 10, '$'
msg_cr     db 13, '$'
msg_crlf   db 13, 10, '$'

track   db 0
lowest  db 0
highest db 0
drive   dw 0
start_addr dd 0
end_addr   dd 0
play_cnt   dd 0
cb      times 16 db 0
req     times 26 db 0
