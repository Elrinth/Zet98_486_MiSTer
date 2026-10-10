; SPDX-License-Identifier: GPL-3.0-or-later
; Segment loads whose selector lies past the GDT or LDT limit must raise
; #GP(selector & FFFCh) without reading past the table. Windows 95's VMM
; reloads a client's segment registers on return ("mov es,[esp+38h]") and
; relies on that #GP to fix up a stale selector; the core read a descriptor
; far past the GDT instead (#PF at C005C9A0), looped and hung after
; "Init = Display Resources". Flat 32-bit ring 0, GDT limit 2Fh, LDT of two
; entries; a descriptor-shaped trap sits right after each table so a missed
; check loads it instead of faulting.
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
dw 0fh, 1000h, 8280h, 0          ; 20h byte-granular LDT at 00801000h (base bit 23 set)
dq 00cf92000000ffffh            ; 28h flat data
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

; case 15: same retry with a system-descriptor selector (18h, the LDT
; descriptor), which faults on any 486 regardless of table limits.
mov ebp,15
mov dword [gp_count],0
mov dword [retry],1
sub esp,40h
mov dword [esp+3ch],18h
mov ds,[esp+3ch]
add esp,40h
mov ax,10h                      ; DS is null now: restore it before any access
mov ds,ax
mov dword [retry],0
mov ecx,[gp_count]
mov esi,[last_err]
cmp dword [gp_count],1
jne fail
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
; case 11: reloading the byte-granular LDT keeps its limit.
mov ebp,11
mov dword [gp_count],0
mov dword [expect],14h
mov dword [resume],.after11
mov ax,18h
lldt ax
mov ax,14h
mov gs,ax
.after11:
mov ax,10h
mov gs,ax
cmp dword [gp_count],1
jne fail
; case 12: a byte-granular LDT whose base has bit 23 set; index 2 is past its
; 16-byte limit. G must come from descriptor bit 55, not base bit 23.
mov ebp,12
mov esi,ldt
mov edi,00801000h
mov ecx,6
rep movsd
mov dword [gp_count],0
mov dword [expect],14h
mov dword [resume],.after12
mov ax,20h
lldt ax
mov ax,14h
mov gs,ax
.after12:
mov ax,10h
mov gs,ax
cmp dword [gp_count],1
jne fail
; case 13: Windows 95 VMM (C00013B7) reloads "mov ds,[esp+3Ch]"; its #GP
; handler nulls the saved selector and returns to the same instruction, which
; must then load the null selector without faulting again.
mov ebp,13
mov ax,18h
lldt ax
mov dword [gp_count],0
mov dword [expect],30h
mov dword [retry],1
sub esp,40h
mov dword [esp+3ch],30h
mov ds,[esp+3ch]
add esp,40h
mov ax,10h                      ; DS is null now: restore it before any access
mov ds,ax
mov dword [retry],0
mov ecx,[gp_count]
mov esi,[last_err]
cmp dword [gp_count],1
jne fail
; case 14: the same through a far pointer register pair (LDS) and ES.
mov ebp,14
mov dword [gp_count],0
mov dword [expect],38h
mov dword [retry],2
sub esp,40h
mov dword [esp+38h],38h
mov es,[esp+38h]
add esp,40h
mov dword [retry],0
mov ax,10h
mov es,ax
cmp dword [gp_count],1
jne fail
mov ax,600dh
jmp report

gp_handler:
push eax
mov ax,10h
mov ds,ax
pop eax
inc dword [gp_count]
cmp dword [gp_count],4
ja fail                         ; a retry that keeps faulting
mov ebx,[esp]                   ; error code
mov [last_err],ebx
cmp dword [retry],0
jne .retry_mode
cmp ebx,[expect]
jne fail
add esp,4
jmp .skip
.retry_mode:
add esp,4
; retry mode: null the saved selector (above the 12-byte frame) and return
; to the faulting instruction, like the VMM handler
mov ebx,[retry]
cmp ebx,1
jne .es_slot
mov dword [esp+12+3ch],0
iretd
.es_slot:
mov dword [esp+12+38h],0
iretd
.skip:
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
retry dd 0
last_err dd 0
fptr dd 12345678h
ptr_sel dw 0
