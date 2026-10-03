; SPDX-License-Identifier: GPL-3.0-or-later
; A store #PF reported after a younger Jcc has already issued (Windows 95
; KERNEL32 at BFF85962: "mov dword [eax],0A0000000h / jne +37h" on a fresh
; not-present page). 32-bit protected mode with paging; each case clears the
; page's present bit, flushes its TLB entry and runs one store followed by a
; conditional jump. The #PF handler checks the vector and CR2, maps the page
; and IRETs; the store must then complete and the jump go the right way.
; Before the fix the fault delivery added the Jcc displacement to the IDT
; gate address and never reached the handler.
; Port 7FE4h prints the registers (EBP = case number); 7FF0h gets 600Dh.
bits 16
cpu 486
org 1000h
P       equ 30ffch              ; last dword of a page, as in KERNEL32
PTE     equ 21000h + (P >> 12) * 4
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
dw 32*8-1
dd IDT
bits 32
pm32:
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,9000h
mov edi,IDT                     ; 32 interrupt gates, all to bad_vector
xor ecx,ecx
.gate:
mov eax,bad_vector
mov edx,eax
and eax,0ffffh
or eax,80000h
and edx,0ffff0000h
or edx,8e00h
cmp ecx,14
jne .not_pf
mov eax,(pf_handler - $$ + 1000h) | 80000h
mov edx,8e00h
.not_pf:
mov [edi+ecx*8],eax
mov [edi+ecx*8+4],edx
inc ecx
cmp ecx,32
jne .gate
lidt [idtr]
mov edi,20000h                  ; identity-map 0-4 MB
mov dword [edi],21000h | 3
mov edi,21000h
mov eax,3
.pte:
stosd
add eax,1000h
cmp edi,22000h
jne .pte
mov eax,20000h
mov cr3,eax
mov eax,cr0
or eax,80000000h
mov cr0,eax
jmp .paged
.paged:

; CASE id, flags, expected path (1 = taken), expected dword, {store}, {jcc}
%macro CASE 6
    mov ebp,%1
    mov dword [faults],0
    mov dword [P],0
    and dword [PTE],0fffffffeh  ; not present
    invlpg [P]
    mov eax,P
    mov ecx,12345678h
    push dword (%2) | 2
    popfd
    %5
    %6 %%taken
    mov ebx,0
    jmp %%join
    times 37h nop               ; keep short jumps at the Win95 distance
%%taken:
    mov ebx,1
%%join:
    cmp dword [faults],1
    jne fail
    cmp ebx,%3
    jne fail
    cmp dword [P],%4
    jne fail
%endmacro

CASE 1, 40h, 0, 0a0000000h, {mov dword [eax],0a0000000h}, jnz short  ; KERNEL32
CASE 2, 0,   1, 0a0000000h, {mov dword [eax],0a0000000h}, jnz short
CASE 3, 40h, 1, 0a0000000h, {mov dword [eax],0a0000000h}, jz near
CASE 4, 0,   0, 0a0000000h, {mov dword [eax],0a0000000h}, jz near
CASE 5, 1,   1, 12345678h,  {mov [eax],ecx},              jc short
CASE 6, 0,   0, 12345678h,  {mov [eax],ecx},              jc near
CASE 7, 80h, 1, 5,          {mov byte [eax],5},           js short
mov ax,600dh
jmp report

pf_handler:
inc dword [faults]
push eax
mov eax,cr2
cmp eax,P
jne fail
mov eax,[esp+4]                 ; error code: write, not present, CPL 0
cmp eax,2
jne fail
or dword [PTE],1                ; present again
invlpg [P]
pop eax
add esp,4
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
faults dd 0
