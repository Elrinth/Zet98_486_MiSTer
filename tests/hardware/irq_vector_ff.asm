; SPDX-License-Identifier: GPL-3.0-or-later
; External interrupt whose acknowledge returns vector FFh (no PIC drives the
; bus: a spurious request). With a 96-entry IDT (limit 2FFh, as Windows 95's
; VMM) the 486 raises #GP with error code 7FBh (index FFh, IDT, EXT); with a
; full IDT (-DFULL_IDT) gate 255 runs. The vector must index the IDT as an
; unsigned byte: a sign-extended FFh reads the gate below the IDT base
; (Windows 95 on the core: #PF at IDT-4, ring-0 stack overflow, hang after
; "Init = Display Resources"). A gate planted just below the IDT catches that.
; Uses z486_xms_resident_tb with PIT_PM_TEST=1 IRQ_VECTOR=8'hff: IRQ0 every
; 10000 clocks while port 02h bit 0 is clear. 7FF0h gets 600Dh.
bits 16
cpu 486
org 1000h
IDT     equ 22000h
cli
xor ax,ax
mov ds,ax
lgdt [gdtr]
mov eax,cr0
or al,1
mov cr0,eax
jmp dword 8:pm32
align 8
gdt:
dq 0
dq 00cf9a000000ffffh            ; 08h flat code
dq 00cf92000000ffffh            ; 10h flat data
gdtr:
dw $-gdt-1
dd gdt
idtr:
%ifdef FULL_IDT
dw 100h*8-1
%else
dw 60h*8-1
%endif
dd IDT
bits 32
pm32:
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,9000h
mov edi,IDT-8                   ; gate "-1" below the IDT, then 256 gates
mov ecx,-1
.gate:
mov eax,bad_vector
cmp ecx,-1
jne .not_below
mov eax,below
.not_below:
cmp ecx,13
jne .not_gp
mov eax,gp_handler
.not_gp:
cmp ecx,0ffh
jne .not_ff
mov eax,vec_ff
.not_ff:
mov edx,eax
and eax,0ffffh
or eax,80000h
and edx,0ffff0000h
or edx,8e00h
mov [edi+8+ecx*8],eax
mov [edi+8+ecx*8+4],edx
inc ecx
cmp ecx,100h
jne .gate
lidt [idtr]
%ifdef SOFT_INT
mov ebp,2                       ; software INT DCh past the IDT limit
mov ecx,3
.soft:
int 0dch
loop .soft
cmp dword [hits],3
jne fail
mov dword [hits],0
mov byte [phase],1               ; next #GPs come from the IRQ
%endif
mov ebp,1
mov al,0feh                     ; unmask IRQ0
out 2,al
sti
mov ecx,200000
.wait:
cmp dword [hits],3
jae .done
loop .wait
jmp fail
.done:
cli
mov al,0ffh                     ; IRQ0 masked again
out 2,al
mov ax,600dh
jmp report

gp_handler:                     ; short IDT: #GP(7FBh) for vector FFh
%ifdef FULL_IDT
jmp fail
%else
%ifdef SOFT_INT
cmp byte [phase],0
jne .irq_gp
cmp dword [esp],0dch*8+2        ; INT DCh: IDT, not external
jne fail
add esp,4
add dword [esp],2               ; skip the INT (CD DC)
inc dword [hits]
iretd
.irq_gp:
%endif
cmp dword [esp],0ffh*8+3
jne fail
add esp,4
inc dword [hits]
mov al,20h                      ; EOI
out 0,al
iretd
%endif
vec_ff:
%ifndef FULL_IDT
jmp fail
%else
inc dword [hits]
mov al,20h                      ; EOI
out 0,al
iretd
%endif
below:
mov ebp,0be10h
jmp fail
bad_vector:
mov ebp,0eeeeh
fail:
mov dx,7fe4h
out dx,ax
mov ax,0deadh
report:
mov dx,7ff0h
out dx,ax
hlt
jmp $
align 4
hits dd 0
phase db 0
