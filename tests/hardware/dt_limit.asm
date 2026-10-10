; SPDX-License-Identifier: GPL-3.0-or-later
; Segment loads whose selector lies past the GDT or LDT limit must raise
; #GP(selector & FFFCh) without reading past the table. Windows 95's VMM
; reloads a client's segment registers on return ("mov es,[esp+38h]") and
; relies on that #GP to fix up a stale selector; the core read a descriptor
; far past the GDT instead (#PF at C005C9A0), looped and hung after
; "Init = Display Resources". Flat 32-bit ring 0, GDT limit 2Fh, LDT of two
; entries; a descriptor-shaped trap sits right after each table so a missed
; check loads it instead of faulting. Case 10: a page-granular LDT (G=1)
; scales its limit like any segment, so index 2 is inside it.
; 7FF0h gets 600Dh; on failure EBP holds the case and EBX the error code.
bits 16
cpu 486
org 1000h
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
dw ldt_end-ldt-1, ldt-0, 8200h, 0 ; 18h LDT (base patched below)
dq 00cf92000000ffffh            ; 20h flat data
dw 0, ldt-0, 8200h, 0080h       ; 28h the same LDT, page-granular (G=1, limit 0 = 4 KB)
gdt_end:
dq 00cf92000000ffffh            ; 30h past the limit: a valid-looking data trap
gdtr:
dw gdt_end-gdt-1
dd gdt
ldt:
dq 00cf92000000ffffh            ; 04h flat data
dq 00cf92000000ffffh            ; 0Ch flat data
ldt_end:
dq 00cf92000000ffffh            ; 14h past the LDT limit: trap
idtr:
dw 20h*8-1
dd IDT
IDT     equ 22000h
bits 32
pm32:
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,9000h
mov edi,IDT
xor ecx,ecx
.gate:
mov eax,bad_vector
cmp ecx,13
jne .not_gp
mov eax,gp_handler
.not_gp:
mov edx,eax
and eax,0ffffh
or eax,80000h
and edx,0ffff0000h
or edx,8e00h
mov [edi+ecx*8],eax
mov [edi+ecx*8+4],edx
inc ecx
cmp ecx,20h
jne .gate
lidt [idtr]
mov ax,18h
lldt ax

; CASE n, selector, {load}: the load must #GP(selector & FFFCh) and be skipped
%macro CASE 3
    mov ebp,%1
    mov dword [gp_count],0
    mov dword [expect],(%2) & 0fffch
    mov word [ptr_sel],%2
    mov eax,%2
    mov dword [resume],%%after
    %3
%%after:
    mov ax,10h                  ; restore flat selectors
    mov ds,ax
    mov es,ax
    mov fs,ax
    mov gs,ax
    cmp dword [gp_count],1
    jne fail
%endmacro

CASE 1, 30h, {mov ds,ax}        ; past GDT limit (index 6)
CASE 2, 38h, {mov es,ax}
CASE 3, 0ffe8h, {mov fs,ax}     ; far past the GDT
CASE 4, 14h, {mov gs,ax}        ; past LDT limit (LDT index 2)
CASE 5, 17h, {mov es,ax}        ; RPL 3: error code drops the RPL
CASE 6, 30h, {mov ss,ax}
CASE 7, 30h, {lfs ebx,[fptr]}
CASE 8, 30h, {les ebx,[fptr]}
; case 9: POP DS of a past-limit selector
mov ebp,9
mov dword [gp_count],0
mov dword [expect],30h
mov dword [resume],.after9
mov eax,30h
push eax
pop ds
.after9:
add esp,4                       ; the faulting POP left its slot in place
mov ax,10h
mov ds,ax
cmp dword [gp_count],1
jne fail
mov ax,10h
mov ss,ax
; case 10: with a page-granular LDT (limit 0, G=1 -> 4 KB) selector 14h
; (index 2) lies inside the table and must load without a fault.
mov ebp,10
mov dword [gp_count],0
mov dword [expect],0ffffh
mov dword [resume],.after10
mov ax,28h
lldt ax
mov ax,14h
mov gs,ax
.after10:
mov ax,10h
mov gs,ax
cmp dword [gp_count],0
jne fail
mov ax,600dh
jmp report

gp_handler:
inc dword [gp_count]
mov ebx,[esp]                   ; error code
cmp ebx,[expect]
jne fail
add esp,4
mov eax,[resume]                ; skip the faulting load
mov [esp],eax
iretd
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
gp_count dd 0
expect dd 0
resume dd 0
fptr dd 12345678h
ptr_sel dw 0
