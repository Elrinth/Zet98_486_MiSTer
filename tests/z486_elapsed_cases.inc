; SPDX-License-Identifier: GPL-3.0-or-later
; Exact SUB/SBB/JNC/ADD/ADC sequence used by cpu_bench.asm elapsed.
    mov word [0x27d0],6
    mov si,elapsed_vectors
    mov cx,elapsed_vector_count
elapsed_vector_next:
    mov eax,0x12340000
    mov edx,0xabcd0000
    mov ax,[si+4]
    mov dx,[si+6]
    sub ax,[si]
elapsed_after_sub:
    sbb dx,[si+2]
    jnc elapsed_no_wrap
    add ax,0x7e40
    adc dx,5
elapsed_no_wrap:
    cmp ax,[si+8]
    jne fail
    cmp dx,[si+10]
    jne fail
    shr eax,16
    shr edx,16
    cmp ax,0x1234
    jne fail
    cmp dx,0xabcd
    jne fail
    add si,12
    loop elapsed_vector_next
    jmp elapsed_vectors_done
elapsed_vectors:
%macro elapsed_case 2
    dd %1,%2,((%2)-(%1)+360000) % 360000
%endmacro
    elapsed_case 0,0
    elapsed_case 0,1
    elapsed_case 65535,65536
    elapsed_case 65530,66530
    elapsed_case 131070,131075
    elapsed_case 262140,263140
    elapsed_case 359999,0
    elapsed_case 359950,50
    elapsed_case 359000,500
    elapsed_case 1,0
    elapsed_case 65535,0
    elapsed_case 65536,0
    elapsed_case 131072,65535
    elapsed_case 262144,131071
    elapsed_case 359999,359999
    elapsed_case 0,359999
%unmacro elapsed_case 2
elapsed_vector_count equ ($-elapsed_vectors)/12
elapsed_vectors_done:
