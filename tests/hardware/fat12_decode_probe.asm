; SPDX-License-Identifier: GPL-3.0-or-later
; Read-only CPU isolation for incorrect DOS FAT12 free-cluster decisions.
; Synthetic table: clusters 2..1088 link to the next, 1089 ends the chain,
; and 1090..1199 are free. No disk writes or private DOS data are used.
bits 16
cpu 386
org 100h
    cli
    mov ax,cs
    mov ss,ax
    mov sp,0fffeh
    mov ds,ax
    cld
    sti
    mov bp,32
again:
    mov bx,2
next_cluster:
    mov si,bx
    shr si,1
    add si,bx
    mov eax,0a5a50000h
    mov ax,[fat+si]
    test bl,1
    jz even_cluster
    mov cl,4
    shr ax,cl
even_cluster:
    and ax,0fffh
decoded:
    test ax,ax
    jz free_cluster
    cmp bx,1090
    jae fail
    mov dx,bx
    inc dx
    cmp bx,1089
    jne compare_value
    mov dx,0fffh
compare_value:
    cmp ax,dx
    jne fail
    jmp check_upper
free_cluster:
    cmp bx,1090
    jb fail
check_upper:
    mov edx,eax
    shr edx,16
    cmp dx,0a5a5h
    jne fail
    inc bx
    cmp bx,1200
    jb next_cluster
    dec bp
    jnz again
    mov dx,passed
    jmp report
fail:
    ; Print first so DOS/video/IRQ I/O cannot replace the final debug index.
    push ax
    push bx
    mov dx,failed
    mov ah,9
    int 21h
    pop bx
    pop ax
    cli
    ; The final UART snapshot retains the bad cluster index at port 7ff0h.
    mov dx,7ff2h
    out dx,ax
    mov ax,bx
    mov dx,7ff0h
    out dx,ax
    jmp park_hlt
report:
    mov ah,9
    int 21h
park:
    cli
park_hlt:
    hlt
    jmp park_hlt
passed: db 'PASS: FAT12 decode, odd/even entries, free-cluster branches,',13,10
        db 'partial registers; 32 scans of 1198 entries. No disk writes.',13,10,'$'
failed: db 'FAIL: FAT12 decode / free-cluster decision. Index on debug port.',13,10,'$'
fat:
%assign cluster 0
%rep 600
%assign first ((cluster+1) & 0fffh)
%assign second ((cluster+2) & 0fffh)
%if cluster == 0
%assign first 0ff0h
%assign second 0fffh
%endif
%if cluster == 1088
%assign second 0fffh
%endif
%if cluster >= 1090
%assign first 0
%assign second 0
%endif
    db first & 255, ((first >> 8) & 15) | ((second & 15) << 4), second >> 4
%assign cluster cluster+2
%endrep
    db 0
    dw decoded-$$,park_hlt-$$,fat-$$
times 0 * (1 / (($ - $$) < 1f00h)) db 0
