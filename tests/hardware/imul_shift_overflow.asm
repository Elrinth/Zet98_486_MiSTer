; SPDX-License-Identifier: GPL-3.0-or-later
; IMUL after a shift whose count reached the operand width. The shifter keeps an
; "overflow" bit for SHL/SHR/SAR counts >= width (the result is 0 or the sign).
; LDBSRM, the count load in front of the IMUL product SHIFT (and a few other
; microcode SHIFTs), left that bit set, so IMUL returned 0 (or FFFF after SAR)
; whenever the last shift instruction had overflowed: Creamy Mami's text routine
; ends with SHR AL,CL (CL = 8) and its next script line index came back as 0.
; Port 7FE4h gets a bit mask of the failing cases (bit N = case N, also in DI),
; 7FF0h gets 600Dh when all pass.
bits 16
cpu 486
org 1000h
cli
xor ax,ax
mov ds,ax
mov ss,ax
mov sp,9000h
xor di,di

%macro check 1
    je %%ok
    or di,1 << %1
%%ok:
%endmacro

; 1: SHR AL,CL with CL=8, then IMUL r16,r/m16,imm8 (6B)
    mov al,0ffh
    mov cl,8
    shr al,cl
    mov si,0ch
    imul ax,si,51h
    cmp ax,3cch
    check 1

; 2: SHL BX,CL with CL=16, then IMUL r16,r/m16,imm16 (69)
    mov bx,1234h
    mov cl,16
    shl bx,cl
    imul dx,si,1234h
    cmp dx,0da70h
    check 2

; 3: SAR DX,CL with CL=20 on a negative value, then IMUL r16,r/m16 (0F AF)
    mov dx,8000h
    mov cl,20
    sar dx,cl
    mov ax,7
    imul ax,si
    cmp ax,54h
    check 3

; 4: SHR AL,8 (immediate form), then IMUL r32,r/m32,imm32
    mov al,80h
    shr al,8
    mov esi,0ch
    imul eax,esi,12345h
    cmp eax,0da73ch
    check 4

; 5: SHL AH,CL with CL=31, then IMUL r16,m16,imm8 (memory source)
    mov word [val],-5
    mov ah,1
    mov cl,31
    shl ah,cl
    imul cx,[val],3
    cmp cx,-15
    check 5

; 6: SAR EAX,CL is masked to 0..31 and never overflows a dword; SAR AX,16 does.
;    Then IMUL r32,r/m32 (0F AF)
    mov ax,8000h
    mov cl,16
    sar ax,cl
    mov eax,100001h
    mov ebx,30h
    imul eax,ebx
    cmp eax,3000030h
    check 6

; 7: the exact Creamy Mami order: overflowing SHR, a store of the source, IMUL
    mov al,0c3h
    mov cl,8
    shr al,cl
    mov ax,3000h
    mov es,ax
    mov si,0ch
    mov [es:6],si
    imul ax,si,51h
    add ax,0ah
    cmp ax,3d6h
    check 7

; 8: no shift in front: on the old shifter case 7's overflow still reached this IMUL
    mov si,7
    imul ax,si,-3
    cmp ax,-21
    check 8

; 9: a shift below the width clears the state (passes on the old shifter too)
    mov al,0c3h
    mov cl,8
    shr al,cl
    shl bx,1
    mov si,9
    imul ax,si,7
    cmp ax,63
    check 9

    mov ax,600dh
    test di,di
    jz report
    mov ax,di
    mov dx,7fe4h
    out dx,ax
    mov ax,0deadh
report:
    mov dx,7ff0h
    out dx,ax
    hlt
    jmp $

val dw 0
