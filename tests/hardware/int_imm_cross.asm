; SPDX-License-Identifier: GPL-3.0-or-later
; INT imm8 whose immediate byte is fetched separately from its CD opcode.
; Windows 95 KERNEL (16-bit protected mode) checks for a debugger with
; "mov ax,4Fh / int 41h"; on the core the gate read went to IDT entry 0
; (the #DE handler), an endless fault loop that hung Windows at USER's
; "Display Resources" step. Each case runs INT 41h placed across a page or
; 16-byte line boundary, with the next page cached, flushed or not present,
; from 32-bit and 16-bit code. The 41h handler counts; every other vector
; except #PF fails. Port 7FE4h prints the registers (EBP = case number);
; 7FF0h gets 600Dh.
bits 16
cpu 486
org 1000h
X       equ 30fffh              ; CD at the last byte of a page, 41h on the next
XPTE    equ 21000h + (31000h >> 12) * 4
L       equ 3200fh              ; CD at the last byte of a 16-byte line
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
dq 00009a030000ffffh            ; 18h 16-bit code, base 30000h
gdtr:
dw $-gdt-1
dd gdt
idtr:
dw 42h*8-1
dd IDT
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
cmp ecx,14
jne .not_pf
mov eax,pf_handler
.not_pf:
cmp ecx,41h
jne .not_41
mov eax,int41
.not_41:
mov edx,eax
and eax,0ffffh
or eax,80000h
and edx,0ffff0000h
or edx,8e00h
mov [edi+ecx*8],eax
mov [edi+ecx*8+4],edx
inc ecx
cmp ecx,42h
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
; 32-bit stubs: CD 41 C3 at X and L
mov dword [X],0c341cdh
mov dword [L],0c341cdh
mov dword [S16],0cb6641cdh      ; int 41h / o32 retf in 16-bit code, CD at a page end

%macro RUN32 2                  ; case, target (setup code precedes)
    mov ebp,%1
    mov dword [hits],0
    mov eax,4fh
    call %2
    cmp dword [hits],1
    jne fail
%endmacro

mov dword [faults],0
RUN32 1, X                      ; warm
invlpg [31000h]
RUN32 2, X                      ; next page not in TLB
and dword [XPTE],0fffffffeh
invlpg [31000h]
RUN32 3, X                      ; next page not present: #PF, then the INT
cmp dword [faults],1
jne fail
invlpg [30000h]
invlpg [31000h]
RUN32 4, X                      ; both pages cold
RUN32 5, L                      ; 16-byte line crossing
wbinvd
RUN32 6, X                      ; cold cache
; 16-bit code segment, as Windows' KERNEL
%assign c 7
%rep 3
    mov ebp,c
    mov dword [hits],0
%if c == 8
    invlpg [S16+1]
%elif c == 9
    and dword [S16PTE],0fffffffeh
    invlpg [S16+1]
%endif
    mov eax,4fh
    call 18h:S16-30000h
    cmp dword [hits],1
    jne fail
%assign c c+1
%endrep
mov ax,600dh
jmp report

S16     equ 33fffh
S16PTE  equ 21000h + (34000h >> 12) * 4

int41:
inc dword [hits]
cmp ax,4fh
jne fail
iretd
pf_handler:
inc dword [faults]
or dword [XPTE],1               ; present again
or dword [S16PTE],1
invlpg [31000h]
invlpg [34000h]
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
hits dd 0
faults dd 0
