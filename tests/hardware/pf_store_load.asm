; SPDX-License-Identifier: GPL-3.0-or-later
; A store #PF reported after a younger load already reached writeback. The
; fault restarts at the store, so the younger load's register write must be
; cancelled: "mov [eax],ecx / mov ecx,[esi]" must store the old ECX. Each case
; clears the page's present bit, flushes its TLB entry, warms the load line,
; then runs the store and the load. The #PF handler checks CR2, maps the page
; and IRETs; [P] must hold the stored value and the register the loaded one.
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
    mov dword [warm],0cafef00dh
    mov dword [warm2],055aa1234h

; CASE id, setup, store, load, second load, expected [P], register, value
%macro CASE 8
    mov ebp,%1
    mov dword [faults],0
    mov dword [P],0
    and dword [PTE],0fffffffeh  ; not present
    invlpg [P]
    mov eax,P
    mov esi,warm
    mov ecx,12345678h
    mov edx,0
    mov ebx,[esi]               ; warm the load line
    %2
    %3
    %4
    %5
    cmp dword [faults],1
    jne fail
    cmp dword [P],%6
    jne fail
    cmp %7,%8
    jne fail
%endmacro

CASE 1, nop,         {mov [eax],ecx},              {mov ecx,[esi]},   nop,              12345678h,  ecx, 0cafef00dh
CASE 2, nop,         {mov [eax],ecx},              {mov ecx,[esi+4]}, nop,              12345678h,  ecx, 055aa1234h
CASE 3, {mov edx,77h}, {mov [eax],dl},             {mov edx,[esi]},   nop,              77h,        edx, 0cafef00dh
CASE 4, nop,         {mov [eax],ecx},              {add ecx,[esi]},   nop,              12345678h,  ecx, 12345678h+0cafef00dh
CASE 5, nop,         {mov dword [eax],0a0000000h}, {mov eax,[esi]},   nop,              0a0000000h, eax, 0cafef00dh
CASE 6, nop,         {mov [eax],ecx},              {mov ecx,[esi]},   {mov ecx,[esi+4]}, 12345678h, ecx, 055aa1234h
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
warm dd 0
warm2 dd 0
align 4
faults dd 0
