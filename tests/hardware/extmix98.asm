; SPDX-License-Identifier: GPL-3.0-or-later
; EXTMIX.COM: DOS-extender-like traffic. Each round switches to protected
; mode (CR0.PE), copies a conventional-memory buffer to extended RAM and back
; at moving, unaligned offsets, returns to real mode, takes interrupts and a
; DOS call, then verifies the round trip. Prints rounds and mismatch counts.
bits 16
cpu 486
org 100h

ROUNDS  equ 4000
BUFA    equ 4000h               ; 16 KB source, COM-relative
BUFB    equ 8000h               ; 16 KB destination
BLEN    equ 4000h

start:
    mov ax,cs
    movzx eax,ax
    shl eax,4
    mov [linbase],eax
    mov [gdt+08h+2],ax
    mov [gdt+18h+2],ax
    mov [gdt+20h+2],ax
    shr eax,16
    mov [gdt+08h+4],al
    mov [gdt+18h+4],al
    mov [gdt+20h+4],al
    mov eax,[linbase]
    add eax,gdt
    mov [gdtr+2],eax
    mov [rmseg],cs
    ; source pattern
    mov di,BUFA
    mov cx,BLEN/2
    xor ax,ax
.init: stosw
    add ax,3D35h
    loop .init
    out 0f2h,al                 ; A20 on
round_top:
    cli
    mov [savesp],sp
    lgdt [gdtr]
    mov eax,cr0
    or al,1
    mov cr0,eax
    jmp dword 08h:pm32
back16:
    mov ax,20h
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov eax,cr0
    and al,0feh
    mov cr0,eax
    jmp far [rmjmp]
rmback:
    mov ax,cs
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,[savesp]
    sti
    mov ah,2ch                  ; DOS get time (interrupts and DOS in between)
    int 21h
    mov cx,200
.idle: loop .idle
    ; verify B == A
    cld
    mov si,BUFA
    mov di,BUFB
    mov cx,BLEN/4
    repe cmpsd
    je .ok
    inc dword [errors]
    cmp dword [errors],1
    jne .ok
    mov eax,[round]
    mov [first_round],eax
    sub si,4
    mov [first_off],si
.ok:
    ; zero B so a dropped copy cannot pass
    mov di,BUFB
    mov cx,BLEN/4
    xor eax,eax
    rep stosd
    ; perturb A
    mov si,BUFA
    mov cx,BLEN/4
    mov eax,[round]
.pert: add [si],eax
    add si,4
    loop .pert
    inc dword [round]
    cmp dword [round],ROUNDS
    jb round_top
    mov al,3
    out 0f6h,al                 ; A20 off
    mov dx,s_rounds
    mov ah,9
    int 21h
    mov eax,[round]
    call hex32
    mov dx,s_err
    mov ah,9
    int 21h
    mov eax,[errors]
    call hex32
    mov dx,s_first
    mov ah,9
    int 21h
    mov eax,[first_round]
    call hex32
    mov dx,s_off
    mov ah,9
    int 21h
    movzx eax,word [first_off]
    call hex32
    mov dx,s_crlf
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h

hex32:
    mov cx,8
.h: rol eax,4
    push eax
    and al,0fh
    add al,'0'
    cmp al,'9'
    jbe .p
    add al,7
.p: mov dl,al
    mov ah,2
    int 21h
    pop eax
    loop .h
    ret

bits 32
pm32:
    mov ax,10h
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov esp,0F00000h - 16
    mov ebp,[cs:linbase]
    mov ebx,[ebp+round]
    ; extended target: 2-12 MB, moving, unaligned
    mov eax,ebx
    imul eax,eax,4111
    and eax,0BFFFFFh
    add eax,200001h
    add eax,ebx
    and eax,09FFFFFh            ; 2-12 MB: clear of the stack and 15 MB hole
    or eax,200000h
    mov edx,eax
    ; scribble near the target with a store pattern first
    mov edi,edx
    and edi,0FFFFF000h
    sub edi,1000h
    mov ecx,(BLEN+3000h)/4
    mov eax,ebx
    rep stosd
    ; low A -> extended (dword copy, unaligned destination)
    lea esi,[ebp+BUFA]
    mov edi,edx
    mov ecx,BLEN/4
    rep movsd
    ; extended -> low B (byte copy for the first 3 bytes, then dwords)
    mov esi,edx
    lea edi,[ebp+BUFB]
    movsb
    movsb
    movsb
    mov ecx,BLEN/4-1
    rep movsd
    movsb
    jmp 18h:back16

bits 16
align 8
gdt:
    dq 0
    dq 00cf9a000000ffffh         ; 08h code32, base patched
    dq 00cf92000000ffffh         ; 10h flat data
    dq 00009a000000ffffh         ; 18h code16, base patched
    dq 000092000000ffffh         ; 20h data16, base patched
gdtr:
    dw 5*8-1
    dd 0
linbase dd 0
savesp  dw 0
rmjmp   dw rmback
rmseg   dw 0
round   dd 0
errors  dd 0
first_round dd 0
first_off dw 0
s_rounds db 'EXTMIX rounds $'
s_err   db ' errors $'
s_first db ' first round $'
s_off   db ' off $'
s_crlf  db 13,10,'$'
