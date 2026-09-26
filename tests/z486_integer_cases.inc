; SPDX-License-Identifier: GPL-3.0-or-later
; Architectural integer arithmetic, followed by the failing diagnostic's
; exact DOS-time conversion with known input/output vectors. DS must be RAM;
; 27d0h is scratch, and the includer provides a fail label.
    mov word [0x27d0],1
    mov eax,0xa5a51280
    mov edx,0x55667788
    mov bl,3
    mul bl
arith_after_mul8:
    pushf
    pop di
    cmp eax,0xa5a50180
    jne fail
    cmp edx,0x55667788
    jne fail
    and di,0x801
    cmp di,0x801
    jne fail
    mov al,255
    xor bl,bl
    mul bl
    pushf
    pop di
    test ax,ax
    jnz fail
    test di,0x801
    jnz fail
    mov eax,0x1122ffff
    mov edx,0x55660000
    mov bx,0x8001
    mul bx
    cmp eax,0x11227fff
    jne fail
    cmp edx,0x55668000
    jne fail
    mov eax,0xfffffff1
    mov ebx,23
    mul ebx
    cmp eax,(0xfffffff1*23)&0xffffffff
    jne fail
    cmp edx,(0xfffffff1*23)>>32
    jne fail
    mov eax,65535
    mov ebx,65537
    mul ebx
    pushf
    pop di
    cmp eax,0xffffffff
    jne fail
    test edx,edx
    jnz fail
    test di,0x801
    jnz fail

    mov word [0x27d0],2
    mov eax,0x7fffffff
    imul eax,byte 2
    pushf
    pop di
    cmp eax,0xfffffffe
    jne fail
    and di,0x801
    cmp di,0x801
    jne fail
    mov eax,-12345
    imul eax,1234
    pushf
    pop di
    cmp eax,-15233730
    jne fail
    test di,0x801
    jnz fail
    mov eax,0xa5a58000
    mov edx,0xbeef7788
    mov bx,-1
    imul bx
    pushf
    pop di
    cmp eax,0xa5a58000
    jne fail
    cmp edx,0xbeef0000
    jne fail
    and di,0x801
    cmp di,0x801
    jne fail

    mov word [0x27d0],3
    mov eax,0xffff1234
    mov edx,0x11223344
    mov bl,0x56
    div bl
    cmp eax,0xffff1036
    jne fail
    cmp edx,0x11223344
    jne fail
    mov eax,0xaaaaffff
    mov edx,0xbbbb0001
    mov bx,257
    div bx
    cmp eax,0xaaaa01fe
    jne fail
    cmp edx,0xbbbb0001
    jne fail
    mov eax,0xffffffff
    mov edx,1
    mov ecx,65537
    div ecx
    cmp eax,131070
    jne fail
    cmp edx,1
    jne fail

    mov word [0x27d0],4
    mov eax,-12345678
    cdq
    mov ebx,321
    idiv ebx
    cmp eax,-38460
    jne fail
    cmp edx,-18
    jne fail
    mov eax,0xabcd8000
    mov edx,0xcdefffff
    mov bx,32767
    idiv bx
    cmp eax,0xabcdffff
    jne fail
    cmp edx,0xcdefffff
    jne fail
    mov eax,0xffffff80
    mov bl,3
    idiv bl
    cmp eax,0xfffffed6
    jne fail

    mov word [0x27d0],5
    mov si,arith_clock_vectors
    mov bp,arith_clock_count
arith_clock_next:
    mov cx,[si]
    mov dx,[si+2]
    call arith_convert_clock
    cmp ax,[si+4]
    jne fail
    cmp dx,[si+6]
    jne fail
    add si,8
    dec bp
    jnz arith_clock_next
    jmp arith_done

; Same arithmetic/register saves as cpu_bench.asm read_clock, replacing only
; the INT 21h time input with the known CX/DX supplied by the caller.
arith_convert_clock:
    push bx
    push cx
    push si
    push di
    push bp
    push es
    mov si,dx
    xor ax,ax
    mov al,cl
    mov bx,60
    mul bx
    mov bx,si
    mov bl,bh
    xor bh,bh
    add ax,bx
    mov bx,100
    mul bx
    mov bx,si
    xor bh,bh
    add ax,bx
    adc dx,0
    pop es
    pop bp
    pop di
    pop si
    pop cx
    pop bx
    ret

arith_clock_vectors:
%assign arith_m 0
%rep 60
    dw (12<<8)|arith_m, (((arith_m*13) % 60)<<8)|((arith_m*37) % 100)
    dd (arith_m*60+(arith_m*13) % 60)*100+(arith_m*37) % 100
%assign arith_m arith_m+1
%endrep
    dw 0,0
    dd 0
    dw 10,(55<<8)|99
    dd 65599
    dw 21,(50<<8)|99
    dd 131099
    dw 59,(59<<8)|99
    dd 359999
arith_clock_count equ ($-arith_clock_vectors)/8
arith_done:
