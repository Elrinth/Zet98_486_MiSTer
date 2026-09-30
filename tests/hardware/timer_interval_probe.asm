; TIMERTST.COM - BIOS interval timer rate. INT 1Ch AH=02h with CX=1 (10 ms)
; and a callback (INT 07h) that counts and re-arms itself. The main loop counts
; 60 vertical syncs (text GDC status bit 5, ~1.07 s at 56.4 Hz) and prints the
; callback count (expect about 107 = 6Bh) and the main-loop pass count.
        org 100h
        mov ax,cs
        mov es,ax
        mov bx,callback
        mov cx,1
        mov ah,2
        int 1ch
        xor si,si               ; main loop passes (low word)
        mov di,60               ; frames to wait
f1:     inc si
        in al,60h
        test al,20h
        jnz f1                  ; wait for vsync low
f2:     inc si
        in al,60h
        test al,20h
        jz f2                   ; wait for vsync high (one frame)
        dec di
        jnz f1
        mov byte [cs:stop],1
        mov ax,[cs:count]
        mov dx,m1
        call report
        mov ax,si
        mov dx,m2
        call report
        mov ax,4c00h
        int 21h

callback:
        inc word [cs:count]
        cmp byte [cs:stop],0
        jne cbdone
        push ax
        push bx
        push cx
        push es
        mov ax,cs
        mov es,ax
        mov bx,callback
        mov cx,1
        mov ah,2
        int 1ch
        pop es
        pop cx
        pop bx
        pop ax
cbdone: iret

report: push ax
        mov ah,9
        int 21h
        pop ax
        push ax
        mov al,ah
        call hex2
        pop ax
        call hex2
        mov dl,13
        mov ah,2
        int 21h
        mov dl,10
        mov ah,2
        int 21h
        ret
hex2:   push ax
        shr al,4
        call hex1
        pop ax
hex1:   and al,0fh
        add al,'0'
        cmp al,'9'
        jbe out1
        add al,7
out1:   mov dl,al
        mov ah,2
        int 21h
        ret
count   dw 0
stop    db 0
m1      db 'timer callbacks $'
m2      db 'main passes     $'
