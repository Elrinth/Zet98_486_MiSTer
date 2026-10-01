; SPDX-License-Identifier: GPL-3.0-or-later
; 486 CMPXCHG/XADD restart after a faulting memory write (and read).
; 32-bit protected mode with paging (CR0.WP). Each case runs one instruction
; whose destination write faults: #GP through a read-only data segment in
; ES, #PF through a read-only (or not-present) page. The handler checks that
; EAX-EDX, the memory operand and the arithmetic flags still hold their
; values from before the instruction, makes the operand writable and IRETs,
; restarting the instruction, which must then complete normally.
; Port 7FE4h prints the registers (EBP = case number); 7FF0h gets 600Dh.
bits 16
cpu 586                         ; NASM files CMPXCHG under the Pentium
org 1000h
M       equ 40010h              ; operand for the #GP cases
P       equ 30010h              ; operand in the page that faults
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
dq 00cf90000000ffffh            ; 18h flat data, read-only
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
cmp ecx,13
jne .not_gp
mov eax,(gp_handler - $$ + 1000h) | 80000h
mov edx,8e00h
.not_gp:
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
or eax,80010000h                ; PG, WP
mov cr0,eax
jmp .paged
.paged:

; FCASE id, vector, pte_clear_mask, mem, eax, ebx, ecx, edx, flags,
;       exp_mem, exp_eax, exp_ebx, exp_ecx, exp_edx, exp_flags, {instruction}
%macro FCASE 16
    mov ebp,%1
    mov dword [faults],0
%if %2 == 13
    mov dword [M],%4
    mov ax,18h
    mov es,ax
%else
    mov dword [P],%4
    and dword [PTE],%3
    invlpg [P]
%endif
    mov dword [pre_mem],%4
    mov dword [pre_eax],%5
    mov dword [pre_ebx],%6
    mov dword [pre_ecx],%7
    mov dword [pre_edx],%8
    mov dword [pre_flags],(%9) & 8d5h
    mov eax,%5
    mov ebx,%6
    mov ecx,%7
    mov edx,%8
    push dword (%9) | 2
    popfd
    %16
    pushfd
    pop dword [post_flags]
    cmp dword [faults],1
    jne fail
    cmp dword [vector],%2
    jne fail
    cmp eax,%11
    jne fail
    cmp ebx,%12
    jne fail
    cmp ecx,%13
    jne fail
    cmp edx,%14
    jne fail
%if %2 == 13
    cmp dword [M],%10
%else
    cmp dword [P],%10
%endif
    jne fail
    mov eax,[post_flags]
    and eax,8d5h
    cmp eax,%15
    jne fail
%endmacro

; #GP: write through the read-only ES.
FCASE 1, 13, 0, 11111111h, 11111111h, 22222222h, 0, 0, 8d5h, \
      22222222h, 11111111h, 22222222h, 0, 0, 44h, {cmpxchg [es:M],ebx}
FCASE 2, 13, 0, 11111111h, 11111112h, 22222222h, 0, 0, 8d5h, \
      11111111h, 11111111h, 22222222h, 0, 0, 0, {cmpxchg [es:M],ebx}
FCASE 3, 13, 0, 7fffffffh, 0, 1, 0, 0, 0, \
      80000000h, 0, 7fffffffh, 0, 0, 894h, {xadd [es:M],ebx}
FCASE 4, 13, 0, 44335a11h, 9876545ah, 0, 0ffffc3h, 0, 8d5h, \
      4433c311h, 9876545ah, 0, 0ffffc3h, 0, 44h, {cmpxchg [es:M+1],cl}
FCASE 5, 13, 0, 80001234h, 0, 0, 0, 0abcd8001h, 0, \
      00011234h, 0, 0, 0, 0abcd8000h, 801h, {xadd [es:M+2],dx}
FCASE 6, 13, 0, 0aaaa5555h, 0bbbb5556h, 0, 0, 1, 0, \
      0aaaa5555h, 0bbbb5555h, 0, 0, 1, 0, {lock cmpxchg [es:M],dx}
; #PF: write to a read-only page (CPL 0, CR0.WP).
FCASE 11, 14, 0fffffffdh, 11111111h, 11111111h, 22222222h, 0, 0, 8d5h, \
      22222222h, 11111111h, 22222222h, 0, 0, 44h, {cmpxchg [P],ebx}
FCASE 12, 14, 0fffffffdh, 11111111h, 11111112h, 22222222h, 0, 0, 8d5h, \
      11111111h, 11111111h, 22222222h, 0, 0, 0, {lock cmpxchg [P],ebx}
FCASE 13, 14, 0fffffffdh, 7fffffffh, 0, 1, 0, 0, 0, \
      80000000h, 0, 7fffffffh, 0, 0, 894h, {lock xadd [P],ebx}
FCASE 14, 14, 0fffffffdh, 44335a11h, 9876545ah, 0, 0ffffc3h, 0, 8d5h, \
      4433c311h, 9876545ah, 0, 0ffffc3h, 0, 44h, {cmpxchg [P+1],cl}
FCASE 15, 14, 0fffffffdh, 80001234h, 0, 0, 0, 0abcd8001h, 0, \
      00011234h, 0, 0, 0, 0abcd8000h, 801h, {xadd [P+2],dx}
FCASE 16, 14, 0fffffffdh, 0aaaa5555h, 0bbbb5556h, 0, 0, 1, 0, \
      0aaaa5555h, 0bbbb5555h, 0, 0, 1, 0, {cmpxchg [P],dx}
; #PF on the read: not-present page.
FCASE 21, 14, 0fffffffeh, 11111111h, 11111111h, 22222222h, 0, 0, 8d5h, \
      22222222h, 11111111h, 22222222h, 0, 0, 44h, {cmpxchg [P],ebx}
FCASE 22, 14, 0fffffffeh, 7fffffffh, 0, 1, 0, 0, 0, \
      80000000h, 0, 7fffffffh, 0, 0, 894h, {xadd [P],ebx}
mov ax,600dh
jmp report

gp_handler:
mov dword [vector],13
jmp fault_common
pf_handler:
mov dword [vector],14
fault_common:                   ; nothing may have changed yet
inc dword [faults]
cmp eax,[pre_eax]
jne fail
cmp ebx,[pre_ebx]
jne fail
cmp ecx,[pre_ecx]
jne fail
cmp edx,[pre_edx]
jne fail
push eax
mov eax,[esp+16]                ; EAX, error code, EIP, CS, EFLAGS
and eax,8d5h
cmp eax,[pre_flags]
jne fail
mov eax,[M]
cmp dword [vector],13
je .gp_mem
mov eax,cr2
cmp eax,P
jb fail
cmp eax,P+3
ja fail
or dword [PTE],3                ; make the page present and writable
invlpg [P]
mov eax,[P]
.gp_mem:
cmp eax,[pre_mem]
jne fail
mov ax,10h                      ; writable ES, then restart
mov es,ax
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
vector dd 0
pre_mem dd 0
pre_eax dd 0
pre_ebx dd 0
pre_ecx dd 0
pre_edx dd 0
pre_flags dd 0
post_flags dd 0
