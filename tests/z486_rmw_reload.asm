; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored regression for a memory increment followed by a reload of the
; same stack word. Watcom C 9.x loop tails use this shape, for example:
;   inc dword [ebp-0Ch] / add edi,1Ch / mov eax,[abs] / add eax,[ebp-20h]
;   mov edx,[ebp-0Ch] / cmp edx,[eax] / jl loop
; Every loop is also counted in a register. A stale reload shows up as an
; extra or missing iteration. Frames live in cached low RAM and in DDR, and
; the body issues calls, stack stores and data-cache misses between tails.
bits 16
cpu 486
org 100h
start:
    cli
    cld
    mov ax,cs
    mov ds,ax
    xor al,al
    out 0f2h,al                       ; A20 on
    lgdt [gdtr]
    mov eax,cr0
    or al,1
    mov cr0,eax
    jmp dword 8:pm32

bits 32
%ifndef OUTER
%define OUTER 600
%endif
MISS    equ 2000000h                  ; 32 KB miss window in DDR
DEFS_LO equ 7e800h                    ; sprite defs {numframes, frames}
DEFS_HI equ 3000800h
FRAME_LO equ 7f800h
FRAME_HI equ 3001800h
SPRITES_LO equ 7e000h                 ; the "sprites" pointer variable
SPRITES_HI equ 3000000h

%macro TAIL 2                         ; %1=frame-relative spacing variant, %2=sprites var
    inc dword [ebp-0ch]
%if %1 >= 1
    add edi,1ch
%endif
    mov eax,[%2]
    add eax,[ebp-20h]
%if %1 >= 2
    nop
%endif
    mov edx,[ebp-0ch]
    cmp edx,[eax]
%endmacro

pm32:
    mov ax,10h
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov esp,FRAME_LO-40h
    mov dword [SPRITES_LO],DEFS_LO
    mov dword [SPRITES_HI],DEFS_HI
    xor ecx,ecx
.defs:                                ; numframes = 1 + index
    lea eax,[ecx+1]
    mov [DEFS_LO+ecx*8],eax
    mov [DEFS_HI+ecx*8],eax
    mov dword [DEFS_LO+ecx*8+4],0
    mov dword [DEFS_HI+ecx*8+4],0
    inc ecx
    cmp ecx,8
    jb .defs
    mov dword [lfsr_state],0ace1h

    mov ebp,FRAME_LO
    call run_all
    mov ebp,FRAME_HI
    mov esp,FRAME_HI-40h
    call run_all
    mov esp,FRAME_LO-40h
    mov dx,7ff0h
    mov ax,600dh
    out dx,ax
    hlt
    jmp $

; ebp = frame. Runs OUTER passes of four tail spacings.
run_all:
    mov dword [ebp-24h],OUTER
.pass:
    call next_rand
    and eax,7
    shl eax,3
    mov [ebp-20h],eax                 ; sprite index * 8
    mov dword [ebp-28h],0             ; spacing variant
.variant:
    mov dword [ebp-0ch],0
    xor edi,edi
    xor esi,esi
    cmp ebp,FRAME_LO
    jne .hi
    cmp dword [ebp-28h],0
    je .lo0
    cmp dword [ebp-28h],1
    je .lo1
    jmp .lo2
.hi:
    cmp dword [ebp-28h],0
    je .hi0
    cmp dword [ebp-28h],1
    je .hi1
    jmp .hi2

%macro LOOPCOPY 3                     ; label, spacing, sprites var
%1:
    inc esi
    call body
    cmp esi,40
    ja fail
    TAIL %2,%3
    jl %1
    mov eax,[%3]
    jmp check
%endmacro
    LOOPCOPY .lo0,0,SPRITES_LO
    LOOPCOPY .lo1,1,SPRITES_LO
    LOOPCOPY .lo2,2,SPRITES_LO
    LOOPCOPY .hi0,0,SPRITES_HI
    LOOPCOPY .hi1,1,SPRITES_HI
    LOOPCOPY .hi2,2,SPRITES_HI

check:
    add eax,[ebp-20h]
    cmp esi,[eax]                     ; register count vs numframes
    jne fail
    cmp esi,[ebp-0ch]                 ; memory count agrees too
    jne fail
    inc dword [ebp-28h]
    cmp dword [ebp-28h],3
    jb run_all.variant
    dec dword [ebp-24h]
    jnz run_all.pass
    ret

; Clobbers eax/ebx/ecx/edx only. Random 0-3 DDR miss loads, a heap store and
; stack traffic near the caller's frame, as a W_CacheLumpNum call would.
body:
    push ebx
    push ecx
    push esi
    call next_rand
    mov ecx,eax
    and ecx,3
    jz .done
.miss:
    call next_rand
    and eax,7ffch
    mov ebx,[MISS+eax]
    add [MISS+8000h+ecx*4],ebx
    dec ecx
    jnz .miss
.done:
    pop esi
    pop ecx
    pop ebx
    ret

next_rand:                            ; 16-bit Galois LFSR in memory
    mov eax,[lfsr_state]
    shr eax,1
    jnc .keep
    xor eax,0b400h
.keep:
    mov [lfsr_state],eax
    ret

fail:
    mov dx,7fe4h
    out dx,ax                         ; testbench prints registers
    mov dx,7ff0h
    mov ax,0deadh
    out dx,ax
    hlt
    jmp $

lfsr_state equ 7e400h

bits 16
align 8
gdt:
    dq 0
    dq 00cf9a010000ffffh              ; code32, base 10000h (this COM segment)
    dq 00cf92000000ffffh              ; flat data
gdtr:
    dw $-gdt-1
    dd 10000h+gdt
